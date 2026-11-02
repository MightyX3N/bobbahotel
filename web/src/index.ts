import { createServer } from 'node:http';
import { createApp } from './app.ts';
import { loadConfig } from './config.ts';
import { openDb } from './db.ts';

const config = loadConfig();
const db = await openDb(config);
const server = createServer(createApp({ config, db }));
server.listen(config.port, config.host, () => console.log(`Bobba Hotel website on http://${config.host}:${config.port} (${config.version})`));
for (const sig of ['SIGINT', 'SIGTERM'] as const) process.on(sig, () => server.close(() => void db.end().then(() => process.exit(0))));
