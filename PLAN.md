# Bobba Hotel – the plan

This is the rulebook for the project. Code follows this file. If something here needs to change, the file is changed first, and only with the owner's OK.

## What it is
A Habbo-style hotel in the browser: the same feel, scale and behaviour as Habbo, with our own furniture (pixel_Salvaje) and avatars (Cozy Assets).
- `hotel.playbobba.com` is the game.
- `playbobba.com` is the community website.

Licence: **GPL-3.0**. The code is open source. The sprite packs are licensed and are never put in git.

References: Nitro (client) and Arcturus Morningstar (server) are GPL-3, so we may study them and reuse code from them. Habbo's own code is only read to learn how things behave. It is never copied.

## The pieces
One repo, `MightyX3N/bobbahotel`, set up as npm workspaces:

| Folder | What it holds |
|---|---|
| `shared/` | Every network message, defined once with a checked shape (server and client import the same file). Game rules both sides need: tile heights, stacking, pathfinding. |
| `server/` | Node 22 + TypeScript. Authoritative: the server decides everything, the client only asks. SQLite database. |
| `client/` | Vite + PixiJS. Split in two parts that never mix: the **room engine** (draws rooms, furni, avatars) and the **UI** (windows). |
| `content/` | Furni definitions, room layouts, catalogue pages, language files. In git. |
| `website/` | playbobba.com (GitHub Pages). |
| `tools/` | Scripts, such as measuring furni sprites into definitions. |
| `deploy/` | VPS setup and Caddy config. |

## How the server works
- Every room runs on a fixed tick of 500 ms, like Habbo. Walking, rolling and wired all step on that tick.
- It is split into modules with clear borders: accounts, rooms, furni, economy, catalogue, chat, social, admin. A module talks to another module only through its public functions or events, never by reaching into its data.
- Every action goes through a permission check (owner, rights, staff) in one place.
- Login: Steam (OpenID) and guest. Up to 3 hotel accounts per Steam account. Staff are set by SteamID in the config.

## How the client works
- **Room engine:** isometric 64×32 tiles, depth sorting, furni, avatars and chat bubbles. It knows nothing about windows.
- **UI = logic + theme:**
  - Logic, for example "the inventory has these items, clicking Place does this", is written once.
  - A **theme** is a folder holding only the look: window layouts, art and CSS. The first theme, **Bobba**, is based on Nitro's UI (the same windows, layout and look: blue window headers, tab rows, a dark toolbar along the bottom), written as our own code with our own icons, since nitro-react has no licence. More themes can be added later as new folders, without touching the logic.
  - The admin picks one theme for the whole server.
- **Language:** every piece of text comes from a language file. Only English is made now; other languages can be added later as new files, with no code changes. A missing key falls back to English.

## Phones and tablets
- One client for everything: touch works like the mouse (tap to walk, drag to look around, pinch to zoom, double-tap furni, hold for names). On narrow screens the chat box gets its own row and windows open full width.
- Installable as an app (PWA): `client/public/manifest.webmanifest`, icons from `tools/make-icons.mjs`, and `client/public/sw.js`, which only keeps the game's own code (never sprites or game data) and always loads the page fresh when online.

## Furni
- **Definitions** live in `content/furni/<pack>.json` (in git): name, floor or wall, tiles covered, pictures per direction (or mirrored from another direction) and per state (off/on, closed/open; double-click to switch), animation speed, and sit / walk / stack. Fix anything there by hand: size, `scale`, `offset`. No real brand names.
- **Pictures** are the pack's own files under `sprites/<pack folder>/` (never in git, never changed). When the server starts it builds one sprite sheet plus frame list per furni into `sprites/built/furni/` (only when something changed), like Habbo's furni packages.
- **`tools/furni-import.mjs`** makes definitions for a new pack from its pictures: it groups animation frames, directions and states, drops repeated pictures and multi-furni sheets, renames brands, and guesses the rest. Definitions that already exist are kept as they are.
- The **Furni test** public room (staff only) shows every floor furni, to check sizes and looks.

## Mods
- **Content packs:** new furni, layouts, catalogue pages, languages and themes, added as folders, with no code needed.
- **Server plugins:** TypeScript modules loaded at startup that use one documented API: register commands, hook events (enter room, use furni, chat…), and add furni behaviour.
- The base avatar body can be replaced by a pack.

## Running and shipping
- One command runs everything locally: `npm run dev`.
- One command checks everything: `npm run check` (types and tests).
- Pushing to `main` starts GitHub Actions. If the checks pass, it deploys to the VPS over SSH. If the server doesn't answer its health check after the restart, it rolls back by itself.
- The database is backed up every night on the VPS.
- Sprites live at `/opt/bobbahotel/sprites` on the VPS and in `sprites/` locally (git-ignored).

## How we build
1. One step at a time. Every step ends playable, checked and live before the next one starts.
2. `ROADMAP.md` is the checklist. A step is ticked only after it has been played on the live server.
3. Behaviour is matched to Habbo by checking how Habbo, Nitro or Arcturus does it, not by guessing.

## Money: a donation project
Bobba Hotel is not built around real money. People can donate, and a donation gives **Bobba Club** for a length of time based on the amount. Club gives extras (such as Club-only room layouts), never the basics of the game.

## First steps
1. Empty repo setup: workspaces, `dev`, `check`, CI and auto-deploy, with a "hello" page live on hotel.playbobba.com.
2. **First slice:** log in (Steam and guest), enter one room, walk, see a second player walk and chat.
3. UI foundation: theme loader and language files, then the first windows.
4. Then the systems in order: furni → inventory → catalogue → coins → the rest of the roadmap.

## Art licences (checked)
- **pixel_Salvaje, Isometric Interiors** (furniture and tiles): may be used and edited in commercial and non-commercial projects. May not be resold or distributed.
- **Klimmos, Cozy Assets** (avatars): may be used in commercial and non-commercial projects. May not be resold, redistributed or claimed as our own. Credit is not required but is appreciated.
- So: sprites never go into git. They live only on the VPS (`/opt/bobbahotel/sprites`) and in the local git-ignored `sprites/`. The README says the art is not included and belongs to its artists. Both artists are credited in the game's credits.
