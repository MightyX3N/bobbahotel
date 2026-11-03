# Nitro's avatar renderer

`src/nitro/avatar/` is Nitro's avatar code (github.com/billsonnn/nitro-renderer, GPL-3), copied with
its own file names. Lines changed for Lua are marked `[bobba]`:

- JavaScript's true/false for numbers and strings (`bobba/Truthy.ts`; `../test/truthiness.js` finds
  every place), a stable sort as in JavaScript (`bobba/Sort.ts`), hex colours (`bobba/Hex.ts`).
- PixiJS, Nitro's events and its downloaders are stand-ins (`src/pixi`, `src/pixi-proxy`,
  `src/core`, `src/events`, `src/api`): nothing is drawn; the containers and sprites Nitro builds
  are kept, and `src/Avatar.ts` turns them into a list of pictures (asset, place, mirrored, colour).
- `src/bobba/Convert.ts` turns Habbo's avatar XML into the JSON shapes Nitro reads.

`sh ../build.sh` makes `gamemodes/bobbahotel/gamemode/nitro/avatar.lua` (`BOBBA.nitroAvatar`).

## Checking it

Nothing of Habbo's is in this repository, so the check needs a folder made from a game's download
(`garrysmod/data/bobbahotel/habbo/`, after `bobba_habbo_figure`):

    data/        geometry.txt partsets.txt animation.txt figure.txt offset_lay.txt offset_swim.txt
                 (from avatar/client_*/), actions.xml figuremap.xml figuredata.xml (from raw/avatar/)
    hh_human_*/  png/ (the pictures) and manifest.xml, and assets.json (name -> library, offsets, size)

    HABBO_DATA=<folder> sh ../test.sh    # Nitro's TypeScript and avatar.lua: every sprite the same
    node test/imaging.js <folder> && python3 test/compare_habbo.py <folder> <imaging>
                                         # against Habbo's own pictures (bobba_habbo_imaging)
