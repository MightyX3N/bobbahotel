# Nitro's furniture visualizations

`src/nitro/room/object/visualization/` and `src/room/` are Nitro's furniture code
(github.com/billsonnn/nitro-renderer, GPL-3): `FurnitureVisualization`, `FurnitureAnimatedVisualization`,
their data classes and `RoomObjectSpriteVisualization`, copied with their own file names. Lines changed
for Lua are marked `[bobba]` or use `bobba/Truthy.ts`:

- JavaScript's true/false for numbers and strings (`../test/truthiness.js` finds every place), hex
  colours (`bobba/Hex.ts`), keys in JavaScript's order where Nitro loops over an object (`bobba/Keys.ts`).
- PixiJS and Nitro's api are stand-ins (`src/pixi`, `src/pixi-proxy`, `src/core`, `src/api`).
- `src/bobba/Convert.ts` turns a furni's XML (index, visualization, assets, logic) into the JSON
  shapes Nitro reads, as nitro-converter does (except that a layer's z keeps its fraction).
- `src/Furni.ts` drives it the way Nitro's room engine does and gives the pictures to draw:
  `loadType`, `create`, `setState`, `update`, `sprites`.

`sh ../build.sh` makes `gamemodes/bobbahotel/gamemode/nitro/furni.lua` (`BOBBA.nitroFurni`).

## Checking it

Nothing of Habbo's is in this repository, so the check needs furni a game downloaded
(`garrysmod/data/bobbahotel/habbo/raw/furni/`; `bobba_habbo_furni_sample` fetches about 80):

    HABBO_FURNI=<that folder> sh ../test.sh

Each furni is put through every direction, every state and colours, 24 updates each, with the same
random numbers on both sides; every sprite of every update must be the same in Nitro's TypeScript
and in furni.lua (83 furni, 42 480 updates, 163 320 sprites, 0 differ).
