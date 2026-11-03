# Making a Bobba Hotel addon

Everything in the hotel is added the same way: Bobba's own default content is just the first addon.

## Layout

A Workshop addon (or a folder in `garrysmod/addons/`):

```
lua/bobbahotel/addons/<id>/addon.lua    -- required: returns { id, name, version, requires }
lua/bobbahotel/addons/<id>/shared.lua   -- server and players
lua/bobbahotel/addons/<id>/server.lua   -- server only
lua/bobbahotel/addons/<id>/client.lua   -- players only
```

`<id>` is lowercase letters, digits, `_ . -` and must match the `id` in `addon.lua`.
`requires` lists addon ids that must load first; if one is missing or switched off, your addon is skipped
and the reason is shown by `bobba_status`. See `examples/bobba_example`.

Server owners switch addons off with `bobba_disabled_addons "id1,id2"`.

## What you can use

| Call | What it does |
| --- | --- |
| `BOBBA.registry.register(type, id, def, { replace = true }?)` | Add an entry (furni, clothes, windows, ... as those types arrive). Another addon's entry is only replaced with `replace = true`. |
| `BOBBA.registry.get(type, id)`, `.list(type)` | Read entries. |
| `BOBBA.lang.add(code, { key = "text {placeholder}" }, name)` | Add texts or a whole language. `BOBBA.L(key, vars)` reads them. |
| `BOBBA.perms.define(name, { default = "user" \| "admin" \| "superadmin", description })` | A permission, shown in ULX/SAM through CAMI. `BOBBA.perms.has(ply, name)` checks it. |
| `BOBBA.store.migrate(id, { sql, ... })` | Server: create or change your tables, once. sv.db is shared by every gamemode and addon, so start table names and migration ids with your addon id. |
| `BOBBA.store.query(sql, { values })` | Server: SQL with `?` placeholders (values are escaped for you; `BOBBA.util.NULL` for an empty value). |
| `BOBBA.events.on(event, yourId, fn)` / `.emit(event, ...)` | Listen for and announce events. |
| `BOBBA.platform.send(name, table, player?)` / `.receive(name, fn)` | Messages between server and players. Always check what a player sends you. |

Keep shared and server code to plain Lua where you can (no `!=`, `&&`, `//`, `continue`), so it also runs on
the custom server later.

## Starter rooms

The hotel has no rooms for new players of its own; a content pack offers them. A new player (one who never
chose a starter room and owns no room) picks one when they first come in, and gets it decorated, owned by
them, as their home room, with a gift inside. Register as many as you like:

```lua
BOBBA.registry.register("starter_room", "mypack_beach", {
	name = "Beach hut", order = 1, color = { r = 240, g = 200, b = 90 },  -- the picker's card
	layout = "model_a", wallpaper = "101", floor = "202",                 -- ids your planes know
	furni = {
		{ kind = "my_table", x = 6, y = 4, dir = 0 },
		{ kind = "my_window", wall = ":w=7,0 l=6,47 r" },              -- a wall furni: Habbo's wall location
	},
	gift = { kind = "my_lamp", box = "present_gen1", x = 9, y = 8, message = "Welcome!" },
})
```

bobba_habbo registers Habbo's six classic coloured rooms (`habbo_classic_1` ... `_6`); replace or unregister
them to offer your own instead.
