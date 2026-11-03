# Bobba Hotel: Habbo content (development addon)

Downloads Habbo's furniture, avatars and room textures from Habbo's own servers on each player's
PC and unpacks them (SWF -> PNG + XML) into `garrysmod/data/bobbahotel/habbo/`. Nothing of
Habbo's is in this addon. Kept apart from the gamemode so servers can switch it off
(`bobba_disabled_addons bobba_habbo`) or replace it.

Put this folder in `garrysmod/addons/`. Test: `bobba_habbo_test` in the console.

`lib/libdeflate.lua` is LibDeflate by Haoqian He (zlib License, see LICENSE-LibDeflate.txt).

In rooms it draws people (`avatars.lua`), furni (`furni.lua`, placed with `bobba_furni <name>`) and
Habbo's floors and wallpapers (`planes.lua`; `bobba_room_floor <id>` / `bobba_room_wallpaper <id>`,
`bobba_habbo_floors` / `bobba_habbo_wallpapers` list the ids). The floors and wallpapers come from
`local_include/HabboRoomContent.swf` in Habbo's desktop client download.
