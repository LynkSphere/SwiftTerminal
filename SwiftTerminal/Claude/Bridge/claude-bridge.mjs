#!/usr/bin/env node

// Claude Agent SDK Bridge
// Communicates with Swift via stdin/stdout JSON lines.
// Persistent SDK query runtime for multi-turn sessions.

import { query, listSessions, getSessionMessages, renameSession } from "@anthropic-ai/claude-agent-sdk";

// --- State ---

let currentQuery = null;

// Prompt queue for multi-turn: the async iterable stays open,
// allowing us to push new messages for each turn.
let promptResolve = null;
let promptQueue = [];
let promptDone = false;

// Pending approval requests: requestId -> resolve callback
const pendingApprovals = new Map();

// Pending elicitation requests: requestId -> resolve callback
const pendingElicitations = new Map();

// --- Output ---

function send(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

// --- Prompt Queue ---

function createPromptIterable() {
  promptQueue = [];
  promptResolve = null;
  promptDone = false;

  return {
    [Symbol.asyncIterator]() {
      return {
        next() {
          if (promptDone) {
            return Promise.resolve({ value: undefined, done: true });
          }
          if (promptQueue.length > 0) {
            return Promise.resolve({ value: promptQueue.shift(), done: false });
          }
          return new Promise((resolve) => {
            promptResolve = resolve;
          });
        },
        return() {
          promptDone = true;
          if (promptResolve) {
            promptResolve({ value: undefined, done: true });
            promptResolve = null;
          }
          return Promise.resolve({ value: undefined, done: true });
        },
      };
    },
  };
}

function pushMessage(userMsg) {
  if (promptResolve) {
    const resolve = promptResolve;
    promptResolve = null;
    resolve({ value: userMsg, done: false });
  } else {
    promptQueue.push(userMsg);
  }
}

function endPromptIterable() {
  promptDone = true;
  if (promptResolve) {
    const resolve = promptResolve;
    promptResolve = null;
    resolve({ value: undefined, done: true });
  }
}

// --- Message Consumer ---

async function consumeMessages(q) {
  try {
    for await (const message of q) {
      send({ type: "sdk_message", message });
    }
    send({ type: "sdk_done" });
  } catch (err) {
    if (err.name !== "AbortError" && !err.message?.includes("closed") && !err.message?.includes("destroyed")) {
      send({ type: "sdk_error", error: err.message });
    }
    send({ type: "sdk_done" });
  }
}

// --- Permission Handler ---

const FILE_TOOLS = new Set([
  "Read", "Write", "Edit", "Glob", "Grep", "NotebookEdit",
]);

function createCanUseTool(permissionMode) {
  if (permissionMode === "bypassPermissions") return undefined;

  return async (toolName, input, opts) => {
    // In acceptEdits mode, auto-allow file operations
    if (permissionMode === "acceptEdits" && FILE_TOOLS.has(toolName)) {
      return { behavior: "allow" };
    }

    const requestId = opts.toolUseID || `approval_${Date.now()}`;

    send({
      type: "approval_request",
      requestId,
      toolName,
      input,
      toolUseID: opts.toolUseID,
      title: opts.title,
      displayName: opts.displayName,
      description: opts.description,
      decisionReason: opts.decisionReason,
      suggestions: opts.suggestions,
    });

    return new Promise((resolve) => {
      pendingApprovals.set(requestId, resolve);
    });
  };
}

// --- Elicitation Handler (MCP server input requests) ---

function createOnElicitation() {
  return async (request, { signal }) => {
    const requestId = request.elicitationId || `elicit_${Date.now()}`;

    send({
      type: "elicitation_request",
      requestId,
      serverName: request.serverName,
      message: request.message,
      mode: request.mode || "form",
      url: request.url,
      requestedSchema: request.requestedSchema,
    });

    return new Promise((resolve) => {
      pendingElicitations.set(requestId, resolve);

      if (signal) {
        signal.addEventListener("abort", () => {
          if (pendingElicitations.has(requestId)) {
            pendingElicitations.delete(requestId);
            resolve({ action: "cancel" });
          }
        });
      }
    });
  };
}

// --- Cleanup Helpers ---

function denyAllPending(message) {
  for (const [, resolve] of pendingApprovals) {
    resolve({ behavior: "deny", message });
  }
  pendingApprovals.clear();

  for (const [, resolve] of pendingElicitations) {
    resolve({ action: "cancel" });
  }
  pendingElicitations.clear();
}

// --- Command Handlers ---

async function handleStartSession(params) {
  try {
    if (currentQuery) {
      endPromptIterable();
      currentQuery.close();
      currentQuery = null;
    }

    denyAllPending("Session ended");

    const promptIterable = createPromptIterable();

    const initialText = params.initialMessage || "Hello";
    pushMessage({
      type: "user",
      message: { role: "user", content: [{ type: "text", text: initialText }] },
      parent_tool_use_id: null,
    });

    const permMode = params.permissionMode || "default";
    const needsApprovals = permMode === "default" || permMode === "acceptEdits";

    const options = {
      cwd: params.cwd || process.cwd(),
      permissionMode: permMode,
      enableFileCheckpointing: true,
      includePartialMessages: true,
      canUseTool: needsApprovals ? createCanUseTool(permMode) : undefined,
      onElicitation: createOnElicitation(),
      promptSuggestions: params.promptSuggestions ?? false,
      ...(permMode === "bypassPermissions" ? { allowDangerouslySkipPermissions: true } : {}),
      ...(params.model ? { model: params.model } : {}),
      ...(params.effort ? { effort: params.effort } : {}),
      ...(params.thinking ? { thinking: params.thinking } : {}),
      ...(params.resume ? { resume: params.resume } : {}),
      ...(params.resumeSessionAt ? { resumeSessionAt: params.resumeSessionAt } : {}),
      ...(params.continueSession ? { continue: true } : {}),
      ...(params.sessionId ? { sessionId: params.sessionId } : {}),
      ...(params.maxTurns ? { maxTurns: params.maxTurns } : {}),
      ...(params.maxBudget ? { maxBudgetUsd: params.maxBudget } : {}),
      ...(params.allowedTools ? { allowedTools: params.allowedTools } : {}),
      ...(params.contextWindow === "1m" ? { betas: ["context-1m-2025-08-07"] } : {}),
      ...(params.systemPrompt ? { systemPrompt: params.systemPrompt } : {}),
    };

    currentQuery = query({ prompt: promptIterable, options });

    // Start consuming messages in background
    consumeMessages(currentQuery);

    send({ type: "bridge_response", command: "start_session", success: true });
  } catch (err) {
    send({ type: "bridge_error", command: "start_session", error: err.message });
  }
}

async function handleSendMessage(params) {
  if (!currentQuery) {
    send({ type: "bridge_error", command: "send_message", error: "No active session" });
    return;
  }

  const content = [{ type: "text", text: params.text }];

  // Support image attachments
  if (params.images?.length) {
    for (const img of params.images) {
      content.push({
        type: "image",
        source: { type: "base64", media_type: img.mediaType, data: img.data },
      });
    }
  }

  pushMessage({
    type: "user",
    message: { role: "user", content },
    parent_tool_use_id: null,
  });

  send({ type: "bridge_response", command: "send_message", success: true });
}

async function handleRespondToApproval(params) {
  const resolve = pendingApprovals.get(params.requestId);
  if (!resolve) {
    send({ type: "bridge_error", command: "respond_to_approval", error: "No pending approval for " + params.requestId });
    return;
  }

  pendingApprovals.delete(params.requestId);

  if (params.behavior === "allow") {
    resolve({
      behavior: "allow",
      ...(params.updatedPermissions ? { updatedPermissions: params.updatedPermissions } : {}),
    });
  } else {
    resolve({
      behavior: "deny",
      message: params.message || "Denied by user",
      interrupt: params.interrupt || false,
    });
  }

  send({ type: "bridge_response", command: "respond_to_approval", success: true });
}

async function handleRespondToElicitation(params) {
  const resolve = pendingElicitations.get(params.requestId);
  if (!resolve) {
    send({ type: "bridge_error", command: "respond_to_elicitation", error: "No pending elicitation for " + params.requestId });
    return;
  }

  pendingElicitations.delete(params.requestId);

  resolve({
    action: params.action || "decline",
    ...(params.content ? { content: params.content } : {}),
  });

  send({ type: "bridge_response", command: "respond_to_elicitation", success: true });
}

async function handleInterrupt() {
  if (!currentQuery) {
    send({ type: "bridge_error", command: "interrupt", error: "No active session" });
    return;
  }
  try {
    denyAllPending("Interrupted");
    await currentQuery.interrupt();
    send({ type: "bridge_response", command: "interrupt", success: true });
  } catch (err) {
    send({ type: "bridge_error", command: "interrupt", error: err.message });
  }
}

async function handleRewind(params) {
  if (!currentQuery) {
    send({ type: "bridge_error", command: "rewind", error: "No active session" });
    return;
  }
  try {
    const result = await currentQuery.rewindFiles(params.userMessageId, {
      dryRun: params.dryRun || false,
    });
    send({ type: "bridge_response", command: "rewind", success: true, result });
  } catch (err) {
    send({ type: "bridge_error", command: "rewind", error: err.message });
  }
}

async function handleStopTask(params) {
  if (!currentQuery) {
    send({ type: "bridge_error", command: "stop_task", error: "No active session" });
    return;
  }
  try {
    await currentQuery.stopTask(params.taskId);
    send({ type: "bridge_response", command: "stop_task", success: true });
  } catch (err) {
    send({ type: "bridge_error", command: "stop_task", error: err.message });
  }
}

async function handleGetContextUsage() {
  if (!currentQuery) {
    send({ type: "bridge_error", command: "get_context_usage", error: "No active session" });
    return;
  }
  try {
    const usage = await currentQuery.getContextUsage();
    send({ type: "bridge_response", command: "get_context_usage", success: true, result: usage });
  } catch (err) {
    send({ type: "bridge_error", command: "get_context_usage", error: err.message });
  }
}

async function handleSupportedModels() {
  if (!currentQuery) {
    send({ type: "bridge_error", command: "supported_models", error: "No active session" });
    return;
  }
  try {
    const models = await currentQuery.supportedModels();
    send({ type: "bridge_response", command: "supported_models", success: true, models });
  } catch (err) {
    send({ type: "bridge_error", command: "supported_models", error: err.message });
  }
}

async function handleListSessions(params) {
  try {
    const sessions = await listSessions({ dir: params.cwd, limit: params.limit || 50 });
    send({ type: "bridge_response", command: "list_sessions", success: true, sessions });
  } catch (err) {
    send({ type: "bridge_error", command: "list_sessions", error: err.message });
  }
}

async function handleGetSessionMessages(params) {
  try {
    const messages = await getSessionMessages(params.sessionId, { dir: params.cwd });
    send({ type: "bridge_response", command: "get_session_messages", success: true, messages });
  } catch (err) {
    send({ type: "bridge_error", command: "get_session_messages", error: err.message });
  }
}

async function handleRenameSession(params) {
  try {
    await renameSession(params.sessionId, params.title, { dir: params.cwd });
    send({ type: "bridge_response", command: "rename_session", success: true });
  } catch (err) {
    send({ type: "bridge_error", command: "rename_session", error: err.message });
  }
}

async function handleStop() {
  denyAllPending("Session stopped");
  endPromptIterable();
  if (currentQuery) {
    currentQuery.close();
    currentQuery = null;
  }
  send({ type: "bridge_response", command: "stop", success: true });
}

async function handleSetModel(params) {
  if (!currentQuery) {
    send({ type: "bridge_error", command: "set_model", error: "No active session" });
    return;
  }
  try {
    await currentQuery.setModel(params.model);
    send({ type: "bridge_response", command: "set_model", success: true });
  } catch (err) {
    send({ type: "bridge_error", command: "set_model", error: err.message });
  }
}

async function handleSetPermissionMode(params) {
  if (!currentQuery) {
    send({ type: "bridge_error", command: "set_permission_mode", error: "No active session" });
    return;
  }
  try {
    await currentQuery.setPermissionMode(params.mode);
    send({ type: "bridge_response", command: "set_permission_mode", success: true });
  } catch (err) {
    send({ type: "bridge_error", command: "set_permission_mode", error: err.message });
  }
}

// --- Main stdin reader ---

let inputBuffer = "";

process.stdin.setEncoding("utf-8");
process.stdin.on("data", (chunk) => {
  inputBuffer += chunk;
  let newlineIndex;
  while ((newlineIndex = inputBuffer.indexOf("\n")) !== -1) {
    const line = inputBuffer.slice(0, newlineIndex).trim();
    inputBuffer = inputBuffer.slice(newlineIndex + 1);
    if (line) processCommand(line);
  }
});

process.stdin.on("end", () => {
  handleStop();
  process.exit(0);
});

async function processCommand(line) {
  let cmd;
  try {
    cmd = JSON.parse(line);
  } catch {
    send({ type: "bridge_error", error: "Invalid JSON: " + line });
    return;
  }

  const params = cmd.params || {};

  switch (cmd.command) {
    case "start_session":           await handleStartSession(params); break;
    case "send_message":            await handleSendMessage(params); break;
    case "respond_to_approval":     await handleRespondToApproval(params); break;
    case "respond_to_elicitation":  await handleRespondToElicitation(params); break;
    case "interrupt":               await handleInterrupt(); break;
    case "rewind":                  await handleRewind(params); break;
    case "stop_task":               await handleStopTask(params); break;
    case "get_context_usage":       await handleGetContextUsage(); break;
    case "supported_models":        await handleSupportedModels(); break;
    case "list_sessions":           await handleListSessions(params); break;
    case "get_session_messages":    await handleGetSessionMessages(params); break;
    case "rename_session":          await handleRenameSession(params); break;
    case "stop":                    await handleStop(); break;
    case "set_model":               await handleSetModel(params); break;
    case "set_permission_mode":     await handleSetPermissionMode(params); break;
    default: send({ type: "bridge_error", error: "Unknown command: " + cmd.command });
  }
}

send({ type: "bridge_ready" });
