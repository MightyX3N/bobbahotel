---
title: Making an addon
order: 5
description: How hotel addons are laid out, and everything they can add - furni, settings, phone apps, pages, wired boxes, starter rooms, languages.
---

# Making an addon

Everything in the hotel is added the same way: Bobba Hotel's own content is just the first addon. An addon
can add furni, clothes, room layouts, starter rooms, phone apps, the hotel's page, wired boxes, settings,
languages - or change how anything works by listening to the hotel's events.

## Layout

A Workshop addon (or a folder in `garrysmod/addons/`):

```
lua/bobbahotel/addons/<id>/addon.lua    -- required: what it is (below)
lua/bobbahotel/addons/<id>/shared.lua   -- runs on the server and on players' games
lua/bobbahotel/addons/<id>/server.lua   -- server only
lua/bobbahotel/addons/<id>/client.lua   -- players only
```

`<id>` is lowercase letters, digits and `_ . -`, and must match the `id` in `addon.lua`. A working example
is in the repository's `examples/bobba_example`.

```lua
-- addon.lua
return {
	id = "mypack",
	name = "My furni pack",
	version = "1.0",
	requires = {},                     -- addon ids that must load first
	description = "Beach furni and a beach hut starter room",
	author = "You",
	settings = {                       -- shown in the Manage screen (optional)
		{ key = "mypack.price", name = "Beach furni price", type = "number", default = 10, min = 0, max = 1000 },
		{ key = "mypack.waves", name = "Animated waves", type = "bool", default = true,
		  description = "Turn off on slow servers" },
		{ key = "mypack.theme", name = "Theme", type = "choice", default = "day",
		  choices = { { "day", "Day" }, { "night", "Night" } } },
		{ key = "mypack.motd", name = "Beach sign", type = "text", default = "Welcome!", max = 40 },
	},
}
```

If something it `requires` is missing or switched off, the addon is skipped and `bobba_status` says why.
Owners switch addons on and off in the [Manage screen](hosting.html#the-manage-screen); a setting is read
with `BOBBA.store.setting("mypack.price", "10")` (always text; `tonumber` it) and the event
`settingChanged` says when one changes.

Keep shared and server code to plain Lua where you can (no `!=`, `&&`, `//`, `continue`), so it also runs on
the custom server and in the desktop app.

## The basics

| Call | What it does |
| --- | --- |
| `BOBBA.registry.register(type, id, def, { replace = true }?)` | Add an entry: `furni`, `layout`, `starter_room`, `plane_style`, `language`, ... Another addon's entry is only replaced with `replace = true`. |
| `BOBBA.registry.get(type, id)`, `.list(type)`, `.unregister(type, id)` | Read or remove entries. |
| `BOBBA.events.on(event, yourId, fn)` / `.emit(event, ...)` | Listen for and announce events. Return `false` from a listener to say no where an event allows it. |
| `BOBBA.platform.send(name, table, player?)` / `.receive(name, fn)` | Messages between the server and players. Always check what a player sends you. |
| `BOBBA.store.migrate(id, { sql, ... })` | Server: create or change your tables, once. Start table names and migration ids with your addon id. |
| `BOBBA.store.query(sql, { values })`, `.row(...)`, `.transaction(fn)` | Server: SQL with `?` placeholders. Rows come back as text. |
| `BOBBA.store.setting(key, default)`, `.setSetting(key, value)` | The hotel's settings. |
| `BOBBA.perms.define(name, { default = "user" \| "admin" \| "superadmin", description })` | A permission (shown in ULX / SAM through CAMI). `BOBBA.perms.has(ply, name)` checks it. |
| `BOBBA.lang.add(code, { key = "text %name%" }, languageName)` | Texts, or a whole language. `BOBBA.ui.text(key, fallback, vars)` reads them. |

## Events

Listen with `BOBBA.events.on("roomEntered", "mypack", function(room, unit) ... end)`. On the server:

| Event | Arguments | When |
| --- | --- | --- |
| `playerReady` | player | A player's game is ready |
| `roomLoaded` / `roomUnloaded` | room | A room starts / stops (nobody in it) |
| `roomCanEnter` | room, player | Return `false` to keep them out |
| `roomEntered` / `roomLeft` | room, unit | Someone comes in / leaves |
| `unitStepped` | room, unit | Someone stood on a new tile |
| `roomChat` | room, unit, text, kind | Someone talks; return `false` to stop it |
| `unitSign` | room, unit, sign | Someone shows a sign |
| `itemPlaced` / `itemMoved` / `itemRemoved` | room, item, (player) | Furni put down, moved, taken away |
| `itemUsed` | room, item, player | Furni switched, rolled or opened |
| `roomCreated` / `roomDeleted` / `roomSettingsSaved` | room id | |
| `roomPainted` | room id, part, id | New wallpaper, floor or landscape |
| `roomFloorPlanChanged` | room id | |
| `catalogBought` | key, offer, amount | Something bought |
| `giftSent` / `giftOpened` | ... | |
| `walletChanged` / `clubChanged` | key, ... | Money or club changed |
| `tradeDone` | keyA, keyB, itemsA, itemsB | A trade went through |
| `friendsMade` / `friendMessage` / `groupCreated` | ... | |
| `lookChanged` | key, figure, gender | New clothes |
| `starterRoomCreated` | key, room id, def | A new player's room was made |
| `playerReset` | key | A player was started over |
| `settingChanged` | key, value | A hotel setting changed |
| `addonsLoaded` | order | Every addon has loaded |

## Furni

A furni kind is defined on the server with its size and behaviour:

```lua
BOBBA.items.define("mypack_beach_chair", {
	width = 1, length = 2, height = 1,     -- tiles and stacking height
	sit = true,                            -- or lay = true, walk = true
	directions = { 0, 2, 4, 6 },
	states = 2,                            -- states it switches through when used
	logic = "furniture_multistate",        -- Nitro's logic type (dice, gates, rollers, teleports, ...)
	category = "chair",                    -- "teleport", "gate", "roller", "present" change how it works
})
```

A content pack that has *many* furni gives the hotel a lookup instead: `BOBBA.items.resolver = function(kind,
cb) ... cb(def) end` (asked once per kind, may answer later), and on players' games draws them with
`BOBBA.room.furniDrawer(item, info)`, names them with `BOBBA.room.furniInfo(kind)` and draws icons with
`BOBBA.room.furniIcon(...)`. The Habbo addon is a complete example. The catalogue comes from
`BOBBA.catalog.provider = function(cb) cb(pages) end`.

## Starter rooms

New players pick one when they first come in, and get it decorated, owned by them, with a gift inside:

```lua
BOBBA.registry.register("starter_room", "mypack_beach", {
	name = "Beach hut", order = 1, color = { r = 240, g = 200, b = 90 },  -- the picker's card
	layout = "model_a", wallpaper = "101", floor = "202",
	furni = {
		{ kind = "mypack_table", x = 6, y = 4, dir = 0 },
		{ kind = "mypack_window", wall = ":w=7,0 l=6,47 r" },          -- a wall furni: Habbo's wall location
	},
	gift = { kind = "mypack_lamp", box = "present_gen1", x = 9, y = 8, message = "Welcome!" },
})
```

## Phone apps

In the phone look, addons add apps (they show in the App Store):

```lua
-- client.lua
BOBBA.device.app({
	id = "mypack_weather", name = "Weather", color = Color(110, 139, 255), store = true,
	glyph = "M6 16a4 4 0 0 1 0-8 6 6 0 0 1 11.5 1.5A3.5 3.5 0 0 1 17 16z",  -- a 24 x 24 SVG path
	phone = function(ctx)
		local d = ctx.d
		d:rect(0, 0, ctx.w, ctx.h, BOBBA.device.C.paper)
		local top = ctx.top + ctx:header("Weather", { big = true })
		d:text("Sunny, 24°", 22, 20, top + 20, BOBBA.device.C.navy)
	end,
})
BOBBA.device.notify({ app = "mypack_weather", title = "Weather", text = "Rain in the Lobby!" })
```

Apps can also add home screen widgets (`BOBBA.device.widget`) and quick tiles in the shade
(`BOBBA.device.tile`).

## The hotel's page

What players see after checking in is Lua too. Add your own, and the hotel's owner can pick it in the Manage
screen:

```lua
-- client.lua
BOBBA.website.register("mypack_page", {
	name = "Beach page",
	draw = function(d, W, H, site)
		d:rect(0, 0, W, H, Color(255, 236, 200))
		d:text("Welcome to " .. (site.data.name or "the hotel"), 32, 40, 40, Color(40, 30, 20))
		d:button(40, 100, 220, 52, "Enter hotel", "primary", site.enter)
	end,
})
```

`site.data` has the hotel's name, description, who's online, news, events, rooms and your credits.

## Wired boxes

An addon can add its own wired triggers, effects and conditions (server):

```lua
BOBBA.wired.define("mypack_wave", {
	kind = "effect", furni = 0,
	fields = { { type = "text", label = "mypack.wave.text", fallback = "Message:", max = 60 } },
	run = function(room, box, cfg, ctx)
		if ctx.unit then BOBBA.wired.whisper(ctx.unit, cfg.text) end
	end,
})
-- and say which furni is that box
BOBBA.items.define("mypack_wave_box", { width = 1, length = 1, height = 0.5, wired = "mypack_wave" })
```

A trigger defines `matches(room, box, cfg, ctx)` and is fired with `BOBBA.wired.fire(room, "mypack_trigger",
{ unit = ..., item = ... })`; a condition defines `test(room, box, cfg, ctx)`. Field types: `text`, `radio`,
`slider`, `check`, `number`, `date`. The window is drawn from them on players' games - no client code needed.

## Messages

```lua
-- server.lua
BOBBA.platform.receive("mypack.ring", function(player, data)
	local id = tonumber(data.id)                       -- check everything a player sends
	if not id then return end
	BOBBA.platform.send("mypack.rang", { id = id })    -- to everyone (or pass a player / list)
end)
-- client.lua
BOBBA.platform.receive("mypack.rang", function(_, data) print("ring", data.id) end)
BOBBA.platform.send("mypack.ring", { id = 5 })
```

## Good to know

- Name everything after your addon id: tables, settings, permissions, messages, registry ids.
- Never trust a player's message: check types, ranges and that they may do it.
- The Habbo addon shows how a big pack downloads, caches and draws content without stuttering: work is
  split into jobs that give the frame back (`BOBBA.habbo.work`).
