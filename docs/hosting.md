---
title: Running a hotel
order: 3
description: The Manage screen, the hotel's settings, permissions, console commands and the money log.
---

# Running a hotel

Whoever hosts the hotel is its owner. Owners and admins manage it from the **Manage screen**; staff get
their powers from **permissions**, which work with ULX, SAM or anything that speaks CAMI.

## The Manage screen

Open it from the start screen, the hotel's page (*Manage hotel*, bottom left), the phone's Settings, the
desktop app's start screen, or the console (`bobba_manage`). It needs the `bobba.admin.hotel` permission
(admins by default). Four tabs:

**Look** - the hotel's name and what it's about (shown on its page and the start screen), the look players
start in (the pack's choice, phone and tablet, or classic windows), the hotel's colour, which page shows
after checking in, and the news on that page.

**Addons** - every hotel addon found, with what it does and whether it's running. Switch one on or off; it
changes when the hotel starts again, and **Restart now** does that (in Garry's Mod: a map change, everyone
comes back by themselves). Addons with settings have a **Settings** button.

**Settings** - the hotel's own settings and each addon's, checked as you change them (a number stays in its
range, a choice is one of its choices) and saved at once.

**Money log** - every time someone gets or loses credits, duckets, diamonds, club days or furni: buying,
gifts, trades, staff giving, the tutorial's reward, group and event costs. Search by name. (Being paid for
being online isn't logged: it's the same for everyone.)

## The hotel's settings

| Setting | Default | What it does |
| --- | --- | --- |
| Credits / duckets / diamonds to start with | 5000 / 0 / 0 | What a new player has |
| Pay every (seconds) | 900 | Everyone online is paid this often |
| Credits / duckets / diamonds each time | 25 / 50 / 2 | Each pay |
| Trading | on | Players swap furni in rooms that allow it |
| Keep the money log (days) | 90 | 0 keeps it for ever |
| Furni price (credits) | 5 | What each furni in the shop costs |
| Seasonal furni only in season | on | Christmas furni at Christmas, and so on |
| Clubs | Habbo Club | Habbo Club, VIP, or both (HC level 1, VIP everything) |
| Club / VIP prices (diamonds) | 250 / 700, 400 / 1100 | One month and three months |
| A photo (credits) | 2 | Buying a camera shot |
| Making a group (credits) | 100 | |
| Groups one can own | 5 | |
| Most friends | 300 | |
| Putting on an event (credits) | 0 | |
| Longest event (hours) | 3 | |
| Tutorial reward (credits) | 50 | For finishing the first steps |
| Videos | on | The rooms' TVs |
| Video services | youtube | Which ones play |
| Wired scripts | on | The script boxes (see [Wired](wired.html)) |
| Floor plans for club members only | on | The floor plan editor |
| Asleep after (seconds) | 120 | Avatars that do nothing fall asleep |

The Habbo pack adds **Club furni for members only** (on).

## Permissions

Defaults are by rank: `user` (everyone), `admin`, `superadmin`. With ULX or SAM they show up as permissions
you can give to any group.

| Permission | Default | Lets you |
| --- | --- | --- |
| `bobba.room.create` | user | Make rooms |
| `bobba.room.floorplan` | user | Use the floor plan editor in your own rooms |
| `bobba.camera.use` | user | Buy photos |
| `bobba.admin.hotel` | admin | The Manage screen |
| `bobba.admin.settings` | superadmin | Change settings from the console |
| `bobba.staff.anyroom` | admin | Act as owner in every room |
| `bobba.staff.enteranyroom` | admin | Go into any room (locked, password, banned, full) |
| `bobba.staff.unkickable` | admin | Can't be kicked, banned or muted in rooms |
| `bobba.staff.kick` | admin | Kick players out of any room |
| `bobba.staff.place` | admin | Place furni straight from the catalogue |
| `bobba.staff.rares` | admin | The catalogue's staff pages (rares, free) |
| `bobba.staff.deletefurni` | admin | Delete furni for good |
| `bobba.staff.currency` | admin | Give credits, duckets, diamonds and club; read the money log |
| `bobba.staff.reset` | admin | Start players over |
| `bobba.staff.groups` | admin | Delete any group |
| `bobba.staff.noflood` | admin | Never muted for flooding the chat |

## Console commands

| Command | What it does |
| --- | --- |
| `bobba_status` | What's loaded: the hotel's addons, which were skipped and why |
| `bobba_manage` | Opens the Manage screen |
| `bobba_hotel_name <name>` | The hotel's name (Habbo's texts say it too) |
| `bobba_give <player> <credits\|duckets\|diamonds\|hc\|vip> <amount>` | Give (or with a minus, take) money or club days |
| `bobba_give <player> effect <id> [days]` | Give an avatar effect |
| `bobba_economy [player] [n]` | The money log's last lines, for everyone or one player |
| `bobba_wallet_setting [name] [value]` | Money and shop settings from the console |
| `bobba_reset_player [player] [all\|look]` | Start a player over as new, or only their look |
| `bobba_rooms` / `bobba_room <id>` | List every room / go into one |
| `bobba_room_create <layout> <name>` | Make a room and go in |
| `bobba_room_wallheight <n>` | The wall height of the room you're in (-1: the hotel's default) |
| `bobba_default_wallheight <n>` | The hotel's default wall height |
| `bobba_disabled_addons "a,b"` | Addons switched off (the Manage screen sets this for you) |

Players' own settings: `bobba_ui` (phone / habbo), `bobba_ui_scale`, `bobba_zoom_with_ctrl`,
`bobba_setting_movekeys` (0 arrows, 1 WASD while the chat is empty, 2 WASD with Enter to chat),
`bobba_startscreen`, `bobba_videos_volume`.

## Where things are kept

Everything is saved in Garry's Mod's own database (`garrysmod/sv.db`), in tables starting with
`bobbahotel_`. Downloaded content (Habbo's files) is cached in `garrysmod/data/bobbahotel/`. Back up `sv.db`
to back up the hotel.
