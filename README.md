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

## Layout
- `website/`  playbobba.com on GitHub Pages (login, groups, news - landing page for now).
- `client/`   the game, built and served by Caddy from the VPS at hotel.playbobba.com (same host as the server: /ws and /sprites).
- `server/`   the game server. `deploy/` has setup.sh (fresh Ubuntu 24.04), update.sh, Caddyfile and the systemd unit.

## Accounts and admin
- Players log in with Steam (OpenID) or play as a guest with a name. Steam accounts pick a hotel name on first login.
- Staff = Steam IDs in `STAFF_STEAMIDS` (comma separated). The admin panel is at `/admin`: live players, rooms, server health,
  live log, chat search, kick / mute / ban, announcements, restart. It only answers to logged-in staff and same-origin requests.
- `ALLOW_DEV_LOGIN=1` (localhost only) enables a fake `/auth/dev?steamid=...` login for testing. Never set it on the VPS.
