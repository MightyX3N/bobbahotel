# Nitro port

Bobba Hotel uses Nitro's own code (github.com/billsonnn/nitro-renderer, GPL-3) for how rooms are
built and drawn. The TypeScript in `src/` is copied from Nitro (files keep Nitro's names); a few
lines are marked `[bobba]` where a JavaScript true/false check had to be written out for Lua.
`Geometry.ts`, `Projection.ts`, `View.ts` and `Pick.ts` put Nitro's steps together the way Nitro's
room engine calls them.

    sh build.sh   # makes gamemodes/bobbahotel/gamemode/nitro/port.lua (TypeScriptToLua)
    sh test.sh    # runs Nitro's TypeScript and the Lua on every Habbo room layout and compares

`data/habbo_models.json` is Habbo's room layouts from Arcturus's database (GPL-3).
