// Server settings come from environment variables. On the VPS they are in /etc/bobbahotel/env.
import { readFileSync } from 'node:fs';

export interface Config {
  port: number;
  host: string;
  /** Allowed browser origins for the WebSocket. Empty = allow any (local development). */
  allowOrigin: string[];
  /** The git commit this server was built from ("dev" when run from a checkout). */
  version: string;
}

function readVersion(): string {
  try {
    return readFileSync(new URL('../../VERSION', import.meta.url), 'utf8').trim() || 'dev';
  } catch {
    return 'dev';
  }
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const port = Number(env.PORT ?? 8080);
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error(`Bad PORT: ${env.PORT}`);
  return {
    port,
    host: env.HOST ?? '127.0.0.1',
    allowOrigin: (env.ALLOW_ORIGIN ?? '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
    version: readVersion(),
  };
}
