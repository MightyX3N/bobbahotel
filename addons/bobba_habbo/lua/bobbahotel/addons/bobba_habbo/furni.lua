-- Habbo furni in rooms (client): draws furni with Habbo's own pictures, put together by Nitro's
-- furniture visualizations (the gamemode's nitro/furni.lua), animated the way Nitro animates them
-- (24 updates a second). A furni is downloaded the first time it's seen (lib/furnidata.lua);
-- until then it isn't drawn.
--
--   BOBBA.room.furniDrawer(item, info) -> { { depth, x, y, w, h, mouse, hit = fn(mx, my), draw = fn }, ... } or nil
--   BOBBA.room.furniInfo(kind) -> { name, sit, lay, walk, width, length } (from furnidata) or nil
--   BOBBA.room.furniIcon(kind, x, y, w, h, s, alpha, fit) -> drawn?   the furni's icon (Nitro's
--     getFurnitureFloorIcon) in the middle of a box, s screen pixels a pixel (catalogue, inventory)
--   BOBBA.room.furniPreview(kind, x, y, w, h, s, dir) -> drawn?  the furni itself in a box (the
--     catalogue's and inventory's preview, like Nitro's RoomPreviewer)

local H = BOBBA.habbo
local P = BOBBA.platform
local NF = BOBBA.nitroFurni

local FU = { types = {}, loading = {}, failed = {}, instances = setmetatable({}, { __mode = "k" }), materials = {} }
H.furni = FU

-- Nitro's RoomSpriteCanvas updates the visualizations 24 times a second
local ANIMATION_FPS = 24

local function findXml(lib, suffix)
	for name, text in pairs(lib.xml) do
		if name:sub(-#suffix) == suffix then return text end
	end
	return nil
end

-- the kind (Nitro's furniture type) for a furni's file, loaded once
local function typeFor(kind)
	local base, color = H.furniBase(kind)
	if FU.aliases and FU.aliases[base] then base = FU.aliases[base] kind = base end
	local t = FU.types[base]
	if t then return t, color end
	if FU.failed[base] or FU.loading[base] then return nil end
	FU.loading[base] = true
	H.furniLibrary(kind, function(lib, err)
		-- (a poster with no file of its own: Habbo's "poster" file)
		if not lib and H.posterNumber(base) then
			FU.loading[base] = nil
			FU.types[base] = nil
			local t2 = typeFor("poster")
			if t2 then FU.types[base] = t2 return end
			FU.aliases = FU.aliases or {}
			FU.aliases[base] = "poster"
			return
		end
		if not lib then
			FU.failed[base] = tostring(err)
			print("[Bobba] furni " .. kind .. ": " .. tostring(err))
			return
		end
		H.work(function()
			local trees = {}
			for _, part in ipairs({ "index", "visualization", "assets", "logic" }) do
				local text = findXml(lib, "_" .. part)
				if not text then FU.failed[base] = "no " .. part .. " XML" print("[Bobba] furni " .. kind .. ": no " .. part) return end
				trees[part] = H.xml.parse(text, H.yield)
			end
			local images = lib.images
			local ok, made = pcall(NF.loadType, trees, { get = function(name) return images[base .. "_" .. name] end })
			if not ok or not made then
				FU.failed[base] = tostring(made)
				print("[Bobba] furni " .. kind .. ": " .. tostring(made))
				return
			end
			made.images = images
			made.base = base
			-- (a window's hole in the wall: its logic's mask, Nitro's FurnitureWindowLogic)
			made.maskType = (findXml(lib, "_logic") or ""):match('<mask%s+type="([^"]+)"')
			-- (a sound block's sound: its logic's sample, FurnitureSoundBlockLogic)
			local sample = (findXml(lib, "_logic") or ""):match("<sample([^>]*)>")
			if sample then
				made.soundSample = tonumber(sample:match('id="(%d+)"'))
				made.noPitch = sample:match('nopitch="true"') ~= nil or sample:match('noPitch="true"') ~= nil
			end
			H.warm(lib) -- (its pictures read into memory now, a little each frame, not when first drawn)
			FU.types[base] = made
			FU.loading[base] = nil
		end)
	end)
	return nil
end

local function material(path)
	local m = FU.materials[path]
	if not m then
		H.image(path) -- (made into a PNG the first time it's drawn)
		m = P.dataMaterial(path, "noclamp")
		FU.materials[path] = m
	end
	return m
end

-- clicking: is the picture solid there? (Nitro checks the pixel; the PNG the addon wrote is read
-- back once, the first time the mouse is over it)
local alphas = {}
local function solid(img, x, y)
	local a = alphas[img.path]
	if a == nil then
		H.image(img.path)
		a = H.png.alphaReader(P.readData(img.path), H.inflate) or false
		alphas[img.path] = a
	end
	if not a then return true end
	return a(x, y) >= 128
end

-- the hotel's loading screen waits for every furni in the room (asking starts their download)
do
	H.loadingCheck("habbo.furni", function()
		local R = BOBBA.room
		local total, ready = 0, 0
		for _, it in pairs(R and R.items or {}) do
			total = total + 1
			local base = H.furniBase(it.kind)
			if typeFor(it.kind) or FU.failed[base] then ready = ready + 1 end
		end
		return ready == total, total > 0 and ready / total or 1
	end)
end

-- one furni on screen (Nitro's visualization for it, kept while the item is)
local function instance(item, t)
	local e = FU.instances[item]
	if e and e.type == t then return e end
	e = { type = t, furni = NF.create(t), frame = -1 }
	FU.instances[item] = e
	return e
end

-- PixiJS blend modes Habbo's inks use: 1 = add (light), 2 = multiply, 3 = screen
local BLENDS = {
	[1] = function() render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD) end,
	[2] = function() render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD) end,
	[3] = function() render.OverrideBlend(true, BLEND_ONE, BLEND_ONE_MINUS_SRC_COLOR, BLENDFUNC_ADD) end,
}

function FU.draw(item, info)
	local t, color = typeFor(item.kind)
	if not t then return nil end
	local e = instance(item, t)
	local now = info.now
	-- (a stickie's colour is its data's: FurnitureStickieLogic, Habbo's four colours 1 to 4)
	if t.logicType == "furniture_stickie" then
		local hex = tostring(item.data or ""):sub(1, 6):upper()
		color = 4
		for i, c in ipairs({ "9CCEFF", "FF9CFF", "9CFF9C", "FFFF33" }) do if c == hex then color = i end end
	end
	NF.setState(e.furni, { direction = (item.dir or 0) * 45, state = item.state or 0, color = color, time = math.floor(now * 1000) })
	local frame = math.floor(now * ANIMATION_FPS)
	if frame ~= e.frame or e.dirty ~= (item.dir or 0) .. ":" .. (item.state or 0) then
		e.frame = frame
		e.dirty = (item.dir or 0) .. ":" .. (item.state or 0)
		NF.update(e.furni, math.floor(now * 1000))
		e.sprites = NF.sprites(e.furni)
	end
	local k = info.k
	local bx, by = math.floor(info.sx + 0.5), math.floor(info.sy + 0.5)
	local ghost = info.alpha or 1
	local out = {}
	for _, s in ipairs(e.sprites or {}) do
		local img = t.images[t.base .. "_" .. s.source]
		if img then
			local x0, y0 = math.floor(s.x * k + 0.5), math.floor(s.y * k + 0.5)
			local x1, y1 = math.floor((s.x + s.width) * k + 0.5), math.floor((s.y + s.height) * k + 0.5)
			local u, v = img.width / (img.texWidth or img.width), img.height / (img.texHeight or img.height)
			local sx, sy, sw, sh = bx + x0, by + y0, x1 - x0, y1 - y0
			local c = s.color or 0xFFFFFF
			local r, g, b = bit.rshift(c, 16) % 256, bit.rshift(c, 8) % 256, c % 256
			local a = math.floor((s.alpha or 255) * ghost)
			local blend = BLENDS[s.blend]
			out[#out + 1] = {
				depth = s.relativeDepth, x = sx, y = sy, w = sw, h = sh, mouse = not s.ignoreMouse, tag = s.tag,
				hit = function(mx, my)
					local px = math.floor((mx - sx) / sw * s.width)
					local py = math.floor((my - sy) / sh * s.height)
					if s.flipH then px = s.width - 1 - px end
					return solid(img, px, py)
				end,
				draw = function()
					surface.SetMaterial(material(img.path))
					surface.SetDrawColor(r, g, b, a)
					render.PushFilterMag(TEXFILTER.POINT)
					render.PushFilterMin(TEXFILTER.POINT)
					if blend then blend() end
					if s.flipH then
						surface.DrawTexturedRectUV(sx, sy, sw, sh, u, 0, 0, v)
					else
						surface.DrawTexturedRectUV(sx, sy, sw, sh, 0, 0, u, v)
					end
					if blend then render.OverrideBlend(false) end
					render.PopFilterMin()
					render.PopFilterMag()
				end,
			}
		end
	end
	return out
end

-- what furnidata says about a kind (for clicking: is it sat on, walked on; its name)
local fdCache
function FU.info(kind)
	if not fdCache then
		fdCache = false
		H.furnidata(function(fd) fdCache = fd or false end)
	end
	if not fdCache then return nil end
	local base = H.furniBase(kind)
	local f = H.furniEntry(fdCache, kind)
	if not f then return nil end
	local name = f.name
	-- (a poster's name is its number's: Habbo's poster_<n>_name)
	local poster = H.posterNumber(kind)
	if poster then name = BOBBA.lang.has("poster_" .. poster .. "_name") and BOBBA.lang.get("poster_" .. poster .. "_name") or name end
	-- (Habbo's wallpapers, floors and landscapes: put on the room; their names are the inventory's)
	local paint = (f.special == 2 and "wallpaper") or (f.special == 3 and "floor") or (f.special == 4 and "landscape") or nil
	if paint and (name or "") == "" then
		local key = "inventory.furni.item." .. paint .. ".name"
		name = BOBBA.lang.has(key) and BOBBA.lang.get(key) or (paint:sub(1, 1):upper() .. paint:sub(2))
	end
	-- (logic: Nitro's logic type, from the furni's file once it's loaded: furniture_trophy, ...)
	-- (sizeX, sizeZ, centerZ: how big a wall furni is on the wall, Nitro's FURNITURE_SIZE_X / _Z / CENTER_Z,
	-- which FurnitureLogic makes half its height)
	local t = FU.types[base]
	local dims = t and t.logic
	return { name = name, sit = f.sit, lay = f.lay, walk = f.walk, width = f.x, length = f.y, wall = f.wall,
		logic = t and t.logicType or nil, category = f.category, maskType = t and t.maskType or nil, paint = paint,
		sizeX = dims and dims.x or nil, sizeZ = dims and dims.z or nil, centerZ = dims and dims.z / 2 or nil }
end

-- the furni's icon: Nitro's getFurnitureFloorIcon, the furni drawn at size 1 (its "icon"
-- visualization, with its colour), in the middle of a box
local icons = {}
function FU.icon(kind, x, y, w, h, s, alpha, fit)
	local t, color = typeFor(kind)
	if not t then return false end
	local e = icons[kind]
	if not e or e.type ~= t then
		e = { type = t, furni = NF.create(t, 1) }
		icons[kind] = e
		NF.setState(e.furni, { direction = 0, state = 0, color = color, time = 0 })
		NF.update(e.furni, 0)
		e.sprites = NF.sprites(e.furni)
	end
	local list = e.sprites or {}
	if #list == 0 then return false end
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, sp in ipairs(list) do
		x0, y0 = math.min(x0, sp.x), math.min(y0, sp.y)
		x1, y1 = math.max(x1, sp.x + sp.width), math.max(y1, sp.y + sp.height)
	end
	-- (fit: made smaller to fit the box, like a catalogue page's 20 x 20 icon)
	if fit then s = math.min(s, w / math.max(1, x1 - x0), h / math.max(1, y1 - y0)) end
	local bx = math.floor(x + (w - (x1 - x0) * s) / 2 - x0 * s + 0.5)
	local by = math.floor(y + (h - (y1 - y0) * s) / 2 - y0 * s + 0.5)
	local order = {}
	for i, sp in ipairs(list) do order[i] = { sp = sp, z = (sp.relativeDepth or 0) + 3.7e-11 * i } end
	table.sort(order, function(a, b) return a.z > b.z end)
	local filter = (fit and s < 1) and TEXFILTER.LINEAR or TEXFILTER.POINT
	render.PushFilterMag(filter)
	render.PushFilterMin(filter)
	for _, o in ipairs(order) do
		local sp = o.sp
		local img = t.images[t.base .. "_" .. sp.source]
		if img then
			local u, v = img.width / (img.texWidth or img.width), img.height / (img.texHeight or img.height)
			local c = sp.color or 0xFFFFFF
			local blend = BLENDS[sp.blend]
			surface.SetMaterial(material(img.path))
			surface.SetDrawColor(bit.rshift(c, 16) % 256, bit.rshift(c, 8) % 256, c % 256, math.floor((sp.alpha or 255) * (alpha or 255) / 255))
			if blend then blend() end
			local sx, sy = bx + math.floor(sp.x * s + 0.5), by + math.floor(sp.y * s + 0.5)
			local sw, sh = math.floor(sp.width * s + 0.5), math.floor(sp.height * s + 0.5)
			if sp.flipH then surface.DrawTexturedRectUV(sx, sy, sw, sh, u, 0, 0, v)
			else surface.DrawTexturedRectUV(sx, sy, sw, sh, 0, 0, u, v) end
			if blend then render.OverrideBlend(false) end
		end
	end
	render.PopFilterMin()
	render.PopFilterMag()
	return true
end

-- the furni in a box: drawn once at 0, 0 to see how big it is, then in the middle
local previews = {}
function FU.preview(kind, x, y, w, h, s, dir)
	local item = previews[kind]
	if not item then
		item = { id = "preview:" .. kind, kind = kind, state = 0 }
		previews[kind] = item
	end
	item.dir = dir or 2
	local info = { sx = 0, sy = 0, k = s, now = SysTime() }
	local sprites = FU.draw(item, info)
	if not sprites or #sprites == 0 then return false end
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, sp in ipairs(sprites) do
		x0, y0 = math.min(x0, sp.x), math.min(y0, sp.y)
		x1, y1 = math.max(x1, sp.x + sp.w), math.max(y1, sp.y + sp.h)
	end
	info.sx = math.floor(x + (w - (x1 - x0)) / 2 - x0 + 0.5)
	info.sy = math.floor(y + (h - (y1 - y0)) / 2 - y0 + 0.5)
	sprites = FU.draw(item, info)
	for i, sp in ipairs(sprites) do sp.order = (sp.depth or 0) + 3.7e-11 * i end
	table.sort(sprites, function(a, b) return a.order > b.order end)
	for _, sp in ipairs(sprites) do sp.draw() end
	return true
end

-- Sound blocks (FurnitureSoundBlockLogic): when one changes state it plays its sample, higher the
-- higher it stands (two semitones a tile: Math.pow(2, height * 2 / 12), back down past 12)
local function pitchFor(height, noPitch)
	if noPitch then return 1 end
	local h = height * 2
	if h > 12 then h = math.min(0, -12 + ((h - 12) - 1)) end
	return 2 ^ (h / 12)
end

local seenState = setmetatable({}, { __mode = "k" })
hook.Add("Think", "bobba.habbo.soundblocks", function()
	local R = BOBBA.room
	if not R or not R.items then return end
	for _, it in pairs(R.items) do
		local t = FU.types[(H.furniBase(it.kind))]
		if t and t.soundSample then
			local was = seenState[it]
			seenState[it] = it.state
			-- (not when it's first seen: only a change plays)
			if was ~= nil and was ~= it.state then
				local rate = pitchFor(tonumber(it.z) or 0, t.noPitch)
				H.furniSample(t.soundSample, function(path)
					if path and BOBBA.sounds and BOBBA.sounds.playFile then BOBBA.sounds.playFile(path, "furni", rate) end
				end)
			end
		end
	end
end)

BOBBA.room = BOBBA.room or { units = {} }
BOBBA.room.furniIcon = FU.icon
BOBBA.room.furniPreview = FU.preview
BOBBA.room.furniDrawer = FU.draw
BOBBA.room.furniInfo = FU.info
