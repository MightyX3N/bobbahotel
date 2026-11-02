// Arcturus remote control (RCON): one JSON message per TCP connection, answered with
// {"status": 0 ok / 1 player offline / ..., "message": "..."}. Only localhost may connect.
import { connect } from 'node:net';

export interface RconReply {
  status: number;
  message: string;
}

/** Status codes (Arcturus RCONMessage). */
export const RCON = { OK: 0, NOT_FOUND: 1 } as const;

export function rcon(target: { host: string; port: number }, key: string, data: object): Promise<RconReply | null> {
  return new Promise((resolve) => {
    const socket = connect(target.port, target.host);
    let text = '';
    const done = (r: RconReply | null) => {
      socket.destroy();
      resolve(r);
    };
    socket.setTimeout(5000, () => done(null));
    socket.on('error', () => done(null));
    socket.on('data', (d) => (text += d.toString('utf8')));
    socket.on('end', () => {
      try {
        done(JSON.parse(text) as RconReply);
      } catch {
        done(null);
      }
    });
    socket.on('connect', () => socket.write(JSON.stringify({ key, data })));
  });
}
