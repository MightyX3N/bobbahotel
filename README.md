# Bobba Hotel

A Habbo-style hotel in the browser. Play at **hotel.playbobba.com**.

- [PLAN.md](PLAN.md): how the project is built (the rulebook).
- [ROADMAP.md](ROADMAP.md): what is done and what comes next.
- The previous version is kept on the `old-version` branch.

## Running it locally
Needs Node 22.18 or newer (24 recommended).

```
npm install
npm run dev      # game server + client, open http://localhost:5173
npm run check    # type checks and tests (CI runs the same)
npm run build    # production build of the client
```

Sprites are not in the repository (see Licence). Put your copy in `sprites/` at the repo root (`sprites/furni`, `sprites/tiles`, `sprites/cozy`).

## Deploying
Push to `main`. GitHub Actions runs the checks and, if they pass, deploys to the VPS and checks that the new version answers. If it doesn't, the VPS switches back to the previous version by itself. See `deploy/`.

First-time VPS setup (or after changing a file in `deploy/`), as root on the VPS:

```
curl -fsSL https://raw.githubusercontent.com/MightyX3N/bobbahotel/main/deploy/setup.sh | bash
```

## Licence
The code is GPL-3.0 (see [LICENSE](LICENSE)).

The art is **not** included and is not covered by that licence:
- Furniture and tiles: *Isometric Interiors* by pixel_Salvaje
- Avatars: *Cozy Assets* by Klimmos

Both are paid packs that may be used in games but not redistributed. To run your own copy, buy them or use your own art.
