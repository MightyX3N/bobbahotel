import { defineConfig } from 'vite';

// In development the game server runs on :8080 and Vite forwards /api and /ws to it,
// so the browser only ever talks to one address, the same as in production.
const server = 'http://127.0.0.1:8080';

export default defineConfig({
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
