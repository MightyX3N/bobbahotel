import { createApp } from './app.ts';
import { loadConfig } from './config.ts';
import { loadContent } from './content.ts';
import { openDb } from './db.ts';
import { buildFurniSheets } from './furni.ts';

const config = loadConfig();
const db = openDb(config.dbFile);
const content = loadContent(config.contentDir);
// Furni sprite sheets from the licensed pictures (only rebuilt when something changed).
try {
  content.furniSheets = buildFurniSheets(content.furni, config.spritesDir, (msg) => {
    content.furniStatus = msg;
    console.log(msg);
  });
} catch (err) {
  content.furniStatus = `Building furni sprite sheets failed: ${(err as Error).message}`;
  console.error(content.furniStatus);
}
const app = createApp({ config, db, content });

app.server.listen(config.port, config.host, () => {
  console.log(`Bobba Hotel server ${config.version} listening on http://${config.host}:${config.port}`);
});

let stopping = false;
async function stop(signal: string): Promise<void> {
  if (stopping) return;
  stopping = true;
  console.log(`${signal}: shutting down`);
  const force = setTimeout(() => process.exit(1), 5000);
  force.unref();
  await app.close();
  db.close();
  process.exit(0);
}
process.on('SIGINT', () => void stop('SIGINT'));
process.on('SIGTERM', () => void stop('SIGTERM'));
