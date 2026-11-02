# Bobba Hotel (web) - Milestone 1

server/  Node 22+ WebSocket server (ws + built-in SQLite). `npm i && npm start` (env: PORT, DB_FILE). Windows/Linux.
client/  Vite + PixiJS. `npm i && npm run dev`; add `?server=wss://host` to pick a server.
         Build: `VITE_WS=wss://play.example.com npm run build` -> dist/ (GitHub Pages).
data/    rooms.json, made from the gamemode's layouts.

## VPS (Ubuntu)
Install Node 22+ and Caddy, clone the repo, `cd server && npm i`, run `PORT=8080 DB_FILE=/var/lib/hotel/hotel.db npm start` under systemd.
Caddyfile (A record play.example.com -> VPS first):
    play.example.com { reverse_proxy localhost:8080 }
Open only ports 22/80/443. Use SSH keys; never share the root password.

## Sprites (not in the repo)
Put the licensed sprites in `sprites/` next to `server/` (tiles/, cozy/). The server serves only `/sprites/*.png` (set ALLOW_ORIGIN to your Pages origin).
`sprites/` is in .gitignore - the packs' licences forbid redistributing the files.
