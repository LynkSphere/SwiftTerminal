import { execFile } from 'node:child_process';
import { copyFile, mkdir, mkdtemp, readFile, rename, rm } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath, pathToFileURL } from 'node:url';

const packageName = '@anthropic-ai/claude-agent-sdk';
const resources = fileURLToPath(new URL('.', import.meta.url));
const execute = promisify(execFile);

async function npm(args, { cwd } = {}) {
  try {
    const { stdout } = await execute('npm', args, { cwd, timeout: 100_000, maxBuffer: 1024 * 1024 });
    return stdout.trim();
  } catch (error) {
    if (error.code === 'ENOENT') throw new Error('Install Node.js and npm to enable Claude history.');
    throw new Error(`Could not prepare Claude history. Check your connection and try again. ${String(error.stderr || error.message).slice(0, 300)}`);
  }
}

async function usableSDK(path) {
  try {
    const sdk = await import(pathToFileURL(path).href);
    return typeof sdk.listSessions === 'function' && typeof sdk.getSessionInfo === 'function'
      && typeof sdk.deleteSession === 'function';
  } catch {
    return false;
  }
}

export async function prepareSDK(cacheRoot) {
  // Reuse a user-installed package without changing it. Claude Code itself is a separate installation.
  try {
    const require = createRequire(join(homedir(), '.swiftterminal-sdk.cjs'));
    const local = require.resolve(packageName);
    if (await usableSDK(local)) return local;
  } catch { /* No SDK in the user's Node module search paths. */ }
  try {
    const root = await npm(['root', '--global']);
    const global = join(root, packageName, 'sdk.mjs');
    if (await usableSDK(global)) return global;
  } catch { /* A cached SDK remains usable when npm is unavailable. */ }

  const manifest = JSON.parse(await readFile(join(resources, 'package.json'), 'utf8'));
  const version = manifest.dependencies[packageName];
  const directory = join(cacheRoot, version);
  const relativeSDK = join('node_modules', packageName, 'sdk.mjs');
  const cached = join(directory, relativeSDK);
  if (await usableSDK(cached)) return cached;

  await mkdir(cacheRoot, { recursive: true });
  const staging = await mkdtemp(join(cacheRoot, '.install-'));
  try {
    for (const name of ['package.json', 'package-lock.json']) {
      await copyFile(join(resources, name), join(staging, name));
    }
    await npm(['ci', '--ignore-scripts', '--omit=optional', '--legacy-peer-deps', '--no-audit', '--no-fund'], { cwd: staging });
    if (!await usableSDK(join(staging, relativeSDK))) {
      throw new Error('The installed Claude Agent SDK does not support session history. Try again.');
    }
    // Publish only a complete installation, and reuse one another app instance finished first.
    if (!await usableSDK(cached)) {
      await rm(directory, { recursive: true, force: true });
      try {
        await rename(staging, directory);
      } catch (error) {
        if (!await usableSDK(cached)) throw error;
      }
    }
    return cached;
  } finally {
    await rm(staging, { recursive: true, force: true });
  }
}
