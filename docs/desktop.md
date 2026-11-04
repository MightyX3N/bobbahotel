---
title: The desktop app
order: 7
description: Bobba Hotel without Garry's Mod - the same hotel, its own window.
---

# The desktop app

The desktop app runs Bobba Hotel without Garry's Mod: the same gamemode and addons, in a small program of its
own (made with [LÖVE](https://love2d.org)). It reads the hotel's Lua through a copy of the Garry's Mod
functions the hotel uses, so the hotel doesn't know the difference - and nor do the players.

> **Test build.** The desktop app comes with the first release; for now it's built from the repository's
> `desktop` folder.

## Using it

1. Start `Bobba Hotel.exe`. The first time it asks for your `garrysmod` folder (it looks in your Steam
   libraries itself): the gamemode, its addons and any Habbo files Garry's Mod already downloaded come from
   there.
2. The start screen lists your hotels. **Host** one on this computer (like Garry's Mod's singleplayer), or
   check in.
3. Owners and admins have **Manage hotel** right on the start screen.

| Key | Does |
| --- | --- |
| F1 | The console (what the hotel prints; commands like `bobba_give`, `bobba_status`) |
| F2 | Takes out / puts away the phone |
| F11 | Full screen (a borderless window the size of the screen) |
| `disconnect` (console) | Back to the start screen |

Controllers work too: the stick or d-pad walks, A uses, LB picks the next thing, RB turns furni, the right
stick moves a pointer (X clicks, B right-clicks), Y holds a menu wheel, Back quick messages, Start the chat.

## Where things are

- Your hotel (its database, your avatar's picture): `%APPDATA%\BobbaHotel\hotels\local`
- The console's log: `garrysmod\data\bobba_temp\desktop_console.log`

## Safe by design

The hotel's Lua (the gamemode and every addon) runs with what Garry's Mod allows and no more: no running
programs, no files outside `garrysmod/data` for writing, no FFI. An addon that works in Garry's Mod works
here, and can't do anything there it couldn't do in Garry's Mod.
