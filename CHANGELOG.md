# Changelog

Development builds, newest first. Bobba Hotel isn't released yet; these are the steps on the way.

## 0.9 - Wired - 2026-11-04

- **Wired**: Habbo's triggers, effects, conditions and add-ons, run the way Habbo's server does: stacks on a
  tile, conditions that all have to hold, effects with delays, *random* and *unseen* add-ons. Nitro's wired
  windows, choosing furni by clicking them in the room (marked in blue). See [Wired and scripts](docs/wired.html).
- **Script boxes**: Habbo's *Custom Wired* effect and condition run a short Lua script - move and switch
  furni, whisper, teleport, count and remember, wait. Sandboxed (no money, files, network or server) and held
  to step, memory and per-room limits, so an endless loop is stopped, not the hotel. Mistakes show in the box.
- **Teleports link one way**: come unlinked, a **Link** window picks which of your teleports one takes you
  to (any room, several to one); trading one away unlinks it.
- **Typing never moves you**: clicking into any text box (or the chat) turns free movement off until you
  click the room; R and the phone key are letters while you type.

## 0.8 - Running a hotel - 2026-11-04

- **The Manage screen** for the hotel's owner and admins: its look (name, about, news, the UI players start
  in, its colour, its page), its addons (on or off, restart) and their settings, the hotel's own settings,
  and the **money log**.
- **The start screen in Garry's Mod** when you host: pick a hotel, add servers.
- **Trading**, Habbo's way: offer, accept, the countdown, confirm - checked again in one transaction at the
  end. In the classic inventory and the phone's Bag.
- **The economy's log**: every credit, club day and furni in or out, why and with whom (`bobba_economy`).
  Buying pays and gives together or not at all.
- **The classic look's social windows**: the friend list with relationships and search, room invites, the
  messenger with groups' chats, the friend bar, profiles with mottos, and group windows (info, members,
  making one, managing it).

## 0.7 - The phone - 2026-11-04

- **The phone and tablet**, Bobba Hotel's own look: a lock screen, a home screen you arrange (apps,
  widgets, pages, the dock), the shade with quick tiles, notifications.
- Apps for everything: Rooms, Bag, Wallet, Camera, Settings, the Furni, Clothes and Club shops, the floor
  plan, Messages, Groups (with text channels), Calls, Events, Videos and the App Store for addons' apps.
- **Checking in**: a new start screen, the hotel's own page, and addons' Lua sandboxed in the desktop app.
- **Videos**: a TV queue per room, played in sync on the room's TV furni, skip votes.
- Camera photos with furni and people in Garry's Mod; text that would run off the screen wraps.

## 0.6 - Moving freely - 2026-11-04

- **Steering**: walk with the arrow keys, WASD or a controller; an interact button; keys and buttons you
  can change.
- **Free movement**: move at any angle and settle on the tile when you stop; smooth on stairs; others see
  you glide. Rooms choose clicking, free movement or both. Walking starts at once.
- **The floor plan editor**: tiles, heights, the door, wall height and thickness; import and export.
- **Avatar actions**: dances, wave, kiss, laugh, signs, sitting on the floor, idle and blinking, effects,
  the wardrobe.
- **The camera**: a roll of five, photos for your walls, room thumbnails.
- A short **tutorial** for new players; `bobba_reset_player`.
- Rooms' chat settings work; the navigator's room info popover.

## 0.5 - Rooms - 2026-11-04

- **Room settings** (all five tabs), rights, the doorbell and passwords, kick / ban / mute, deleting rooms,
  favourites and the home room, categories and tags, the avatar menu and infostand, the hotel view.
- **Starter rooms**: new players pick a decorated room of their own (packs add them), with a gift inside.
- Windows follow the game window's size.
- The [roadmap](roadmap.html).

## 0.4 - The desktop app - 2026-11-03

- **The desktop app** (test build): the hotel without Garry's Mod, its server on a thread, a start page like
  the old Habbo website, its own icon, borderless full screen.
- A leave button in the me menu.

## 0.3 - Habbo's windows and the shop - 2026-11-03

- **Habbo's UI from nitro-react**: the toolbar, the me menu, the purse, the room tools, the navigator with
  real rooms, the inventory. Sized for your screen (`bobba_ui_scale`).
- **The catalogue**, inventory, credits, duckets, diamonds and **Habbo Club** (HC, VIP or both); every floor
  furni, seasonal furni in season, gifts, the staff rares tab.
- **Furni that do things**: dice, bottles and wheels, gates, one-way gates, rollers, teleports, trophies,
  the background toner; building tools (stacking helper, placing in a row).
- **Wall furni**: posters, windows, shelves, wallpapers, floors, landscapes, stickies, the mood light.
- Habbo's sounds; R turns the furni being placed.

## 0.2 - Habbo's content - 2026-11-03

- **The Habbo addon**: downloads and unpacks Habbo's files on each player's PC; nothing of Habbo's shipped.
- **Avatars**, **furniture** (Nitro's visualizations in Lua: placing, sitting, lying), floors and
  wallpapers.
- **Chat** with Habbo's bubbles, Nitro's layout and word breaks.
- **The avatar editor** with Habbo's clothes and icons; saving looks.
- No stutter while loading: work in jobs, quicker pictures, downloads fetched ahead; Nitro's font.

## 0.1 - A new start - 2026-11-03

- Bobba Hotel starts over as a **Garry's Mod gamemode**: the core, addons, permissions (CAMI / ULX / SAM),
  saving, languages.
- **Rooms** drawn the way Nitro draws them - geometry, camera and picking in Lua - with Habbo's colours, the
  door hole and walls lined up with Habbo's.
- Rooms on the server: entering, walking with Habbo's pathfinder.
- Zoom with Ctrl + scroll, smooth, towards the mouse.
