# Bobba Hotel

A Habbo-style hotel in the browser. Play at **hotel.playbobba.com**.

The previous, self-written version is kept on the `old-version` branch.

## How it is made
Bobba Hotel runs on the open-source Habbo retro stack, with its own art and its own website:

- **Game client: [Nitro](https://github.com/Gurkengewuerz/nitro)** (Gurkengewuerz's fork of the Nitro renderer and Nitro React, GPL-3). We build a pinned version with a small patch (`nitro/renderer.patch`: our avatars' 8-frame animations, and no mirrored avatar directions). Configs are in `nitro/`.
- **Game server: [Arcturus Morningstar](https://github.com/UnfamiliarLegacy/Arcturus)** (GPL-3) with the **[ms-websockets](https://github.com/dank074/ms-websockets)** plugin, built from source by `.github/workflows/arcturus.yml`.
- **Art:** furni, floors, walls and avatars are converted from our licensed packs into Nitro's format by `tools/nitro/` (on the VPS, at every deploy; the art is never in git). The furni list with names, directions and states is decided by hand in `content/furni/catalogue.json`.
- **Website (`web/`):** Steam login, new accounts, the one-time game login ticket, and admin pages (players, club, currency, ranks, catalogue prices).
- **Database:** Arcturus' MariaDB; our changes are in `sql/` (migrations run once each; the furni list on every deploy).

Many thanks to the Nitro and Arcturus developers. **If you are one of them and do not want your work used here, please [open an issue](https://github.com/MightyX3N/bobbahotel/issues) and we will sort it out.**

## Running it locally
Needs Node 22.18 or newer (24 recommended), MariaDB and Java 17.

```
npm install --ignore-scripts
npm run check                                   # type checks and tests (CI runs the same)
node tools/nitro/build-all.mjs build/nitro sprites   # the client's assets from your art
```

Sprites are not in the repository (see Licence). Put your copy in `sprites/` (`sprites/furni`, `sprites/tiles`, `sprites/cozy`, and `sprites/hotelview.png`). See `deploy/` for how the parts fit together.

## Deploying
Push to `main`. GitHub Actions runs the checks, builds the Nitro client and deploys to the VPS, which builds the assets, updates the database and checks that the website and the game server answer. If they don't, it switches back to the previous version by itself.

First-time VPS setup (or after changing a file in `deploy/`), as root on the VPS:

```
curl -fsSL https://raw.githubusercontent.com/MightyX3N/bobbahotel/main/deploy/setup.sh | bash
```

## Licence
The code is GPL-3.0 (see [LICENSE](LICENSE)), as are Nitro and Arcturus.

The art is **not** included and is not covered by that licence:
- Furniture and tiles: *Isometric Interiors* by pixel_Salvaje
- Avatars: *Cozy Assets* by Klimmos

Both are paid packs that may be used in games but not redistributed. To run your own copy, buy them or use your own art.

Bobba Hotel is not affiliated with Sulake or Habbo.
