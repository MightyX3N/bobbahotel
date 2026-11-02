// Step 1 placeholder: a small empty room floor and the connection status.
// The real room engine replaces this in step 2.
import { Application, Container, Graphics } from 'pixi.js';
import { PROTOCOL_VERSION } from '@bobba/shared';
import { Connection, serverUrl } from './net.ts';

const TILE_W = 64;
const TILE_H = 32;
const FLOOR = 0xa47a52;
const FLOOR_EDGE = 0x7d5a3b;
const SIZE = 6;

async function main(): Promise<void> {
  const app = new Application();
  await app.init({ resizeTo: window, background: 0x000000, antialias: false });
  document.getElementById('game')!.appendChild(app.canvas);

  const room = new Container();
  room.addChild(drawFloor());
  app.stage.addChild(room);

  const center = () => {
    room.x = Math.round(app.screen.width / 2);
    room.y = Math.round(app.screen.height / 2 - (SIZE * TILE_H) / 2);
  };
  center();
  app.renderer.on('resize', center);

  const status = document.getElementById('status')!;
  const conn = new Connection(serverUrl());
  conn.onOpen = () => conn.send({ t: 'hello', d: { protocol: PROTOCOL_VERSION } });
  conn.onClose = () => (status.textContent = 'Disconnected, retrying…');
  conn.on('welcome', (d) => (status.textContent = `Connected to Bobba Hotel (server ${d.server.slice(0, 7)})`));
  conn.on('error', (d) => {
    status.textContent = d.message;
    if (d.code === 'old_client') setTimeout(() => location.reload(), 1500);
  });
  conn.connect();
}

function drawFloor(): Graphics {
  const g = new Graphics();
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      const sx = (x - y) * (TILE_W / 2);
      const sy = (x + y) * (TILE_H / 2);
      g.poly([sx, sy, sx + TILE_W / 2, sy + TILE_H / 2, sx, sy + TILE_H, sx - TILE_W / 2, sy + TILE_H / 2])
        .fill(FLOOR)
        .stroke({ color: FLOOR_EDGE, width: 1, alignment: 0.5 });
    }
  }
  return g;
}

void main();
