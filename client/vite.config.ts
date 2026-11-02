import { createReadStream, existsSync, statSync } from 'node:fs';
import { resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig, type Plugin } from 'vite';

// In development the game server runs on :8080 and Vite forwards /api and /ws to it, so the
// browser only ever talks to one address, the same as in production. Sprites come from the
// git-ignored sprites/ folder at the repo root (on the VPS, Caddy serves them).
const server = 'http://127.0.0.1:8080';
const spritesDir = fileURLToPath(new URL('../sprites/', import.meta.url));

function devSprites(): Plugin {
  return {
    name: 'bobba-dev-sprites',
    configureServer(dev) {
      dev.middlewares.use('/sprites', (req, res, next) => {
        const path = decodeURIComponent((req.url ?? '/').split('?')[0]!);
        const file = resolve(spritesDir, '.' + path);
        const type = file.endsWith('.png') ? 'image/png' : file.endsWith('.json') ? 'application/json' : null;
        if (!file.startsWith(spritesDir.replace(/[\\/]$/, '') + sep) || !type || !existsSync(file) || !statSync(file).isFile()) {
          res.statusCode = 404;
          return res.end();
        }
        res.setHeader('content-type', type);
        createReadStream(file).pipe(res);
        void next;
      });
    },
  };
}

export default defineConfig({
  plugins: [devSprites()],
  server: {
    port: 5173,
    proxy: {
      '/api': server,
      '/ws': { target: server, ws: true },
    },
  },
  build: {
    target: 'es2022',
    assetsInlineLimit: 0,
  },
});
