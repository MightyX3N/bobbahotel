---
title: The Habbo addon
order: 6
description: How bobba_habbo gives the hotel Habbo's furni, clothes and look - downloaded on each player's PC, never shipped.
---

# The Habbo addon

`bobba_habbo` is the content pack that makes Bobba Hotel look and feel like Habbo: Habbo's furni, clothes,
rooms, chat bubbles, sounds, icons and windows. **Nothing of Habbo's is in the addon.** Each player's game
downloads what it needs from Habbo's own servers, the way Habbo's own client does, and keeps it in a cache.

It lives apart from the gamemode on purpose: a hotel can switch it off and use other content instead, and
the gamemode never depends on it.

## What it does, step by step

1. **Finds Habbo's files.** It reads Habbo's public client settings (`external_variables`), which say where
   the current furni, figure and text files are.
2. **Reads Habbo's data**: `furnidata` (every furni: name, size, whether you can sit, stand or lie on it),
   `figuredata` (every piece of clothing and colour), and Habbo's texts (so windows say what Habbo says).
3. **Downloads furni and clothes when they're first needed** - a furni the first time someone sees it, not
   all 13 000 at once. Files are Habbo's Flash files (SWF); the addon unpacks them in Lua into pictures and
   their XML.
4. **Draws them the way Nitro does.** The gamemode has Nitro's furniture visualizations and avatar renderer
   rewritten in Lua (layers, directions, animations, colours, shadows), and the addon feeds them Habbo's
   pictures and XML.
5. **Caches everything** in `garrysmod/data/bobbahotel/habbo/` so the next start is instant.

Unpacking happens in small jobs that give the frame back, so loading never stutters the room; pictures are
written uncompressed (ten times quicker); six downloads run at once; and things you're about to need are
fetched ahead.

## What it adds to the hotel

| Part | From Habbo |
| --- | --- |
| Furni | Every floor and wall furni, with Habbo's behaviour (dice, gates, teleports, rollers, trophies, stickies, mood lights, TVs, wired boxes...) |
| The catalogue | Built from furnidata: every furni by its line, families over the years under one page (Habboween 2009 - 2026, Christmas, ...), seasonal pages only in season, Habbo Club furni on the club's tab, rares on a staff tab, posters, stickies, and the Spaces tab (wallpapers, floors, landscapes) |
| Avatars | Habbo's clothes, colours, effects and actions, checked against figuredata like Habbo's server does |
| Rooms | Habbo's room layouts, wallpapers, floors and landscapes; six classic starter rooms |
| The look | Nitro's windows (the classic UI) with Habbo's icons from Habbo's desktop client, the chat bubbles, sounds, the hotel view and a Habbo-style hotel page |

## Settings

- **Club furni for members only** (on): Habbo Club's furni can only be bought by members, as in Habbo.

Shop prices, seasons and clubs are the hotel's own settings (see [Running a hotel](hosting.html)).

## If Habbo can't be reached

A furni that can't be downloaded isn't drawn (and the server leaves furni it can't identify out of the room
until it can); avatars fall back to a stand-in figure. Everything already in the cache keeps working
offline.

## Making your own pack

The Habbo addon is the biggest example of what a content pack does: it answers the hotel's
`BOBBA.items.resolver`, provides `BOBBA.room.furniDrawer` / `furniInfo` / `furniIcon`, the catalogue
provider, starter rooms, plane styles and a hotel page. A pack with its own art does the same with its own
pictures. See [Making an addon](addons.html).
