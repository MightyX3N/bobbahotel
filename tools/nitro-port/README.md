# Nitro port

Bobba Hotel uses Nitro's own code (github.com/billsonnn/nitro-renderer, GPL-3) for how rooms are
built and drawn. The TypeScript in `src/` is copied from Nitro (files keep Nitro's names); a few
lines are marked `[bobba]` where a JavaScript true/false check had to be written out for Lua.
`Geometry.ts`, `Projection.ts`, `View.ts` and `Pick.ts` put Nitro's steps together the way Nitro's
room engine calls them.

    sh build.sh   # makes gamemodes/bobbahotel/gamemode/nitro/port.lua (TypeScriptToLua)
    sh test.sh    # runs Nitro's TypeScript and the Lua on every Habbo room layout and compares

`data/habbo_models.json` is Habbo's room layouts from Arcturus's database (GPL-3).

## The avatar editor

`editor/src/nitro-react/` is nitro-react's avatar editor logic (github.com/billsonnn/nitro-react,
src/api/avatar, GPL-3), unchanged. It was ported by hand to `gamemodes/bobbahotel/gamemode/hotel/
figureeditor.lua`, and `test.sh` (with `HABBO_DATA`) checks the two against each other: the same 60
runs of random clicks (pieces, colours, gender, clear, reset, random) on Habbo's own figuredata,
every category's state compared after every click. `editor/src/Editor.ts` is nitro-react's
AvatarEditorView without React; `renderer-stub.ts`, `nitro.ts` and `figuredata.ts` stand in for the
parts of nitro-renderer it uses.
