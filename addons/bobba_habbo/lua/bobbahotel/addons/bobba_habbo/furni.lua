-- Habbo furni in rooms (client): draws furni with Habbo's own pictures, put together by Nitro's
-- furniture visualizations (the gamemode's nitro/furni.lua), animated the way Nitro animates them
-- (24 updates a second). A furni is downloaded the first time it's seen (lib/furnidata.lua);
-- until then it isn't drawn.
--
--   BOBBA.room.furniDrawer(item, info) -> { { depth, x, y, w, h, mouse, hit = fn(mx, my), draw = fn }, ... } or nil
--   BOBBA.room.furniInfo(kind) -> { name, sit, lay, walk, width, length } (from furnidata) or nil

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
	local t = FU.types[base]
	if t then return t, color end
	if FU.failed[base] or FU.loading[base] then return nil end
	FU.loading[base] = true
	H.furniLibrary(kind, function(lib, err)
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
				depth = s.relativeDepth, x = sx, y = sy, w = sw, h = sh, mouse = not s.ignoreMouse,
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
	local f = fdCache.byClass[kind] or fdCache.byClass[base]
	if not f then return nil end
	return { name = f.name, sit = f.sit, lay = f.lay, walk = f.walk, width = f.x, length = f.y, wall = f.wall }
end

BOBBA.room = BOBBA.room or { units = {} }
BOBBA.room.furniDrawer = FU.draw
BOBBA.room.furniInfo = FU.info
