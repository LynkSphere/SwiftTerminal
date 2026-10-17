import { pathToFileURL } from 'node:url';
import { prepareSDK } from './claude-sdk.mjs';

try {
  if (process.argv[2] === '--prepare') {
    process.stdout.write(await prepareSDK(process.argv[3]));
    process.exit(0);
  }
  const { deleteSession, getSessionInfo, listSessions } = await import(pathToFileURL(process.argv[2]).href);
  if (process.argv[3] === '--delete') {
    const sessionId = process.argv[4];
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(sessionId ?? '')) {
      throw new Error('Invalid Claude session identifier.');
    }
    const options = { dir: process.argv[5] };
    // An unsaved draft (or a session already deleted elsewhere) has no transcript to remove.
    if (await getSessionInfo(sessionId, options)) await deleteSession(sessionId, options);
    process.stdout.write('{}');
    process.exit(0);
  }
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
