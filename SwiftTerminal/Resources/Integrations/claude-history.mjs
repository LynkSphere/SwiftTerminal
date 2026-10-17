import { pathToFileURL } from 'node:url';
import { prepareSDK } from './claude-sdk.mjs';

try {
  if (process.argv[2] === '--prepare') {
    process.stdout.write(await prepareSDK(process.argv[3]));
    process.exit(0);
  }
  const { getSessionInfo, listSessions } = await import(pathToFileURL(process.argv[2]).href);
  const sessionId = process.argv[3];
  const session = sessionId ? await getSessionInfo(sessionId) : undefined;
  const sessions = sessionId ? (session ? [session] : []) : await listSessions({ limit: 25, offset: 0 });
  process.stdout.write(JSON.stringify(sessions.map(session => ({
    sessionId: session.sessionId,
    title: session.customTitle || session.summary || session.firstPrompt || 'Claude thread',
    hasProviderTitle: Boolean(session.customTitle || session.summary),
    cwd: session.cwd ?? '',
    lastModified: session.lastModified,
  }))));
} catch (error) {
  process.stderr.write(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
