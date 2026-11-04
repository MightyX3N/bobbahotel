---
title: Wired and scripts
order: 4
description: Habbo's wired, how stacks run, every box there is, and the script boxes' Lua.
---

# Wired and scripts

Wired is Habbo's way of making rooms do things: furni boxes you stack on a tile. Bobba Hotel runs wired the
way Habbo's server (Arcturus) does, and adds **script boxes** that run a short Lua script.

## How it works

- A **trigger** says when: someone says a word, walks onto a furni, a timer runs out...
- **Conditions** on the same tile say *only if*: they all have to hold.
- **Effects** on the same tile say what happens, each after its own **delay** (0 to 10 seconds).
- **Add-ons**: *random* runs one of the stack's effects at random; *unseen* runs them one after another.

Put the boxes on one tile, double-click each to set it up, and pick its furni by clicking them in the room
while its window is open (they get a blue mark). Anyone with rights in the room can use wired.

Wired can't slow the hotel down: a room runs at most 200 stacks a second, and stacks calling stacks stop
after eight.

## Triggers

| Box | Fires when |
| --- | --- |
| User says keyword | Someone says something with these words in it (any user, or only the owner). Only they see what they said. |
| User walks on / off furni | Someone walks onto or off one of the chosen furni |
| User enters room | Someone comes in (anyone, or someone by name) |
| Furni is used | One of the chosen furni is switched, rolled or opened |
| User clicks furni | Someone clicks one of the chosen furni |
| Repeat effect / Periodically long | Every 0.5 - 30 seconds / every 5 - 600 seconds |
| At set time / At time long | Once, this long after the timers were reset |
| Collision | Furni moved by wired (chase) runs into someone |

## Effects

| Box | Does |
| --- | --- |
| Toggle furni state | Switches the chosen furni to their next state, as if used |
| Toggle to random state | A random state |
| Reset timers | Starts the room's timers again (timed triggers and conditions) |
| Show message | Whispers a message to whoever set it off |
| Teleport to furni | Puts whoever set it off onto one of the chosen furni |
| Kick user | Sends them out of the room (never the owner or staff) |
| Mute user | Mutes them in this room for 1 - 10 minutes |
| Move and rotate furni | Moves the chosen furni a tile (a way, or at random) and turns them |
| Move furni to direction | Keeps them moving a tile at a time; blocked, they turn back |
| Match furni to position and state | Puts the chosen furni back as they were when the box was saved |
| Chase / flee | Moves the chosen furni a tile towards or away from the nearest person |
| Execute wired stacks | Runs the stacks the chosen furni are on |
| **Script (Custom wired effect)** | Runs your Lua script (below) |

## Conditions

Each also has a *NOT* version.

| Box | Only if |
| --- | --- |
| Triggerer is on furni | Whoever set it off is on one of the chosen furni |
| Furni has users | Someone is on each chosen furni |
| Furni has furni on | There's furni on top of any / all of the chosen furni |
| Furni states and positions match | The chosen furni are as they were when saved (state, direction, position) |
| Furni matches | The furni that set it off is one of the chosen (or the same kind) |
| More / less than x seconds | Since the timers were reset |
| User count in room | Between this many and that many people are in the room |
| Group member | Whoever set it off is in the room's group |
| Wearing effect | They have this avatar effect on |
| Date and time | Between two dates |
| **Script (Custom wired condition)** | Your Lua script returns true |

## Script boxes

The *Custom Wired* effect and condition run a short Lua script (up to 4000 letters) in place of fixed
settings. The script only sees what's made for it - the room, its people and furni, who set it off, a little
memory of its own - and can change the room the way wired can. It can't touch money or inventories, make
furni, read files, use the network or reach anything of the server.

```lua
-- an effect: count visitors on a plate, and light a lamp every tenth
memory.count = (memory.count or 0) + 1
say("You're visitor number " .. memory.count)
if memory.count % 10 == 0 then
	local lamp = room.furni("lamp_basic")[1]
	if lamp then lamp:toggle() end
end
```

```lua
-- a condition: only the room's owner sets it off
return user ~= nil and user.isOwner
```

### What a script sees

| Name | What it is |
| --- | --- |
| `user` | Whoever set it off, or `nil` (a timer): `.name .x .y .dir .effect .isOwner`, `:whisper(text)`, `:teleport(x, y)`, `:teleportTo(furni)`, `:kick()` |
| `trigger` | `{ kind = "says" \| "walkson" \| ..., text = what was said, furni = the furni it was about }` |
| `selected` | The furni chosen in the box's window, as a list |
| `room` | `room.users()`, `room.furni([kind])`, `room.get(id)`, `room.count()`, `room.elapsed()`, `room.reset()`, `room.call(furni)` (runs that furni's stack), `room.id`, `room.name`, `room.owner` |
| a furni | `.id .kind .x .y .z .dir .state`, `:setState(n)`, `:toggle()`, `:move(x, y [, dir])`, `:turn(dir)`, `:usersOn()` |
| `memory` | A table kept between runs while the room is loaded: words, numbers, true / false (200 of them) |
| `say(...)` / `print(...)` | Whisper to whoever set it off |
| `random(a, b)` | A whole number from a to b (`random()` 0 to 1) |
| `wait(seconds, fn)` | Runs fn later (at most 30 seconds, ten waiting at once) |
| Lua | `string` (patterns on strings up to 10 000 letters), `math`, `table`, `pairs`, `ipairs`, `tostring`, `tonumber`, `type`, `pcall`, `os.time`, `os.date` |

### Limits

A run may take at most 200 000 steps of Lua and 2 MB more memory; a room's scripts together 2 million steps
a second. A script that goes over is stopped - an endless loop can't freeze the hotel - and its box shows why
the next time it's opened (*Last problem: line 2: ...*), as do mistakes in the script. The owner can switch
script boxes off for the whole hotel (Manage, Settings, *Wired scripts*).
