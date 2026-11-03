-- Habbo avatars in rooms (client): draws people with Habbo's own clothes, put together by Nitro's
-- avatar renderer (the gamemode's nitro/avatar.lua) and placed the way Nitro's AvatarVisualization
-- places them. Everything Habbo comes from Habbo's servers (avatardata.lua, library.lua).
--
-- Everything is loaded when the game starts (from the cache after the first time), so people show
-- up with the room. While a figure's clothes are still on their way, it isn't drawn (just its name);
-- if Habbo can't be reached at all, the room's stand-in figure is drawn instead.

local H = BOBBA.habbo
local P = BOBBA.platform
local NA = BOBBA.nitroAvatar

H.DEFAULT_FIGURE = "hr-100-61.hd-180-1.ch-210-66.lg-270-82.sh-290-80"

local AV = { assets = {}, materials = {}, figures = {}, images = {}, failed = nil }
H.avatars = AV

-- Nitro's AvatarVisualization: an update every 41 ms, a new animation frame every second update
local UPDATE = 0.041
local FRAME_EVERY = 2
local ROOM_SCALE = 64

-- the renderer, made once Habbo's avatar data is here
local function renderer(cb)
	if AV.renderer then cb(AV.renderer) return end
	if AV.waiting then AV.waiting[#AV.waiting + 1] = cb return end
	AV.waiting = { cb }
	H.avatarData(function(data, err)
		if not data then
			AV.waiting = nil
			AV.failed = err
			print("[Bobba] Habbo avatars: " .. tostring(err))
			return
		end
		-- reading the XML is a job (a few milliseconds a frame); making the renderer is one go
		H.work(function()
			local function x(field) return H.avatarXml(data, field) end
			local trees = {
				geometry = x("geometry"), partSets = x("partSets"), animation = x("animation"),
				actions = x("actions"), offsets = { lay = x("offset_lay"), swim = x("offset_swim") },
				figureData = { x("figure") },
			}
			H.figureIndex(data) -- figuremap too, while we're at it
			local ok, r = pcall(NA.createRenderer, trees, { get = function(name) return AV.assets[name] end })
			-- the big figuredata a piece at a time
			if ok then
				ok, r = pcall(function()
					for _, piece in ipairs(H.figureDataPieces(x("figuredata"))) do
						r:appendFigureData(piece)
						H.yield()
					end
					return r
				end)
			end
			local waiting = AV.waiting
			AV.waiting = nil
			if not ok then
				AV.failed = tostring(r)
				print("[Bobba] Habbo avatars: " .. AV.failed)
				return
			end
			AV.renderer = r
			for _, w in ipairs(waiting) do w(r) end
		end)
	end)
end

-- the pictures of a downloaded library, under Habbo's asset names (the manifest has the offsets)
local function addLibrary(lib)
	local name = lib.key:match("([^/]+)$")
	local manifest = lib.xml[name .. "_manifest"] or lib.xml.manifest
	if not manifest then return end
	local X = H.xml
	for _, a in ipairs(X.all(X.parse(manifest, H.yield), "asset")) do
		local img = lib.images[name .. "_" .. a.attrs.name]
		local offset
		for _, p in ipairs(X.children(a, "param")) do
			if p.attrs.key == "offset" then offset = p.attrs.value end
		end
		if img and offset then
			local ox, oy = offset:match("^(%-?%d+),(%-?%d+)")
			AV.assets[a.attrs.name] = {
				offsetX = tonumber(ox), offsetY = tonumber(oy), width = img.width, height = img.height, path = img.path,
				-- the picture is the top-left corner of a power-of-two texture
				u = img.width / (img.texWidth or img.width), v = img.height / (img.texHeight or img.height),
			}
		end
	end
end

-- a figure is ready when every library it needs is loaded
local function figureReady(figure)
	local f = AV.figures[figure]
	if f then return f.ready end
	f = { ready = false }
	AV.figures[figure] = f
	renderer(function()
		H.figureLibraries(figure, function(libs, err)
			if not libs then print("[Bobba] clothes for " .. figure .. ": " .. tostring(err)) return end
			H.work(function()
				for _, lib in ipairs(libs) do addLibrary(lib) end
				f.ready = true
			end)
		end)
	end)
	return false
end

local function material(path)
	local m = AV.materials[path]
	if not m then
		m = P.dataMaterial(path, "noclamp")
		AV.materials[path] = m
	end
	return m
end

-- one avatar image per unit, kept while its figure stays the same
local function imageFor(u, figure)
	local e = AV.images[u.id]
	if e and e.figure == figure then return e end
	e = { figure = figure, image = AV.renderer:createImage(figure, "h"), state = nil, lastUpdate = 0, updates = 0 }
	AV.images[u.id] = e
	return e
end

local function stateKey(info)
	return info.dir .. ":" .. info.posture
end

-- one picture: (px, py) its top-left corner in avatar pixels from the avatar's corner (bx, by) on
-- screen; k screen pixels per avatar pixel. Every edge lands on a whole screen pixel, worked out
-- from the avatar's corner, so the pictures of one avatar always line up with each other.
local function sprite(name, bx, by, px, py, k, flip, color, alpha)
	local a = AV.assets[name]
	if not a then return end
	surface.SetMaterial(material(a.path))
	surface.SetDrawColor(bit.rshift(color, 16) % 256, bit.rshift(color, 8) % 256, color % 256, alpha or 255)
	local x0, y0 = math.floor(px * k + 0.5), math.floor(py * k + 0.5)
	local x1, y1 = math.floor((px + a.width) * k + 0.5), math.floor((py + a.height) * k + 0.5)
	if flip then
		surface.DrawTexturedRectUV(bx + x0, by + y0, x1 - x0, y1 - y0, a.u, 0, 0, a.v)
	else
		surface.DrawTexturedRectUV(bx + x0, by + y0, x1 - x0, y1 - y0, 0, 0, a.u, a.v)
	end
end

local function draw(u, info)
	if AV.failed then return false end
	local figure = (u.figure and u.figure ~= "") and u.figure or H.DEFAULT_FIGURE
	if not AV.renderer then renderer(function() end) end
	-- still on its way: draw nothing rather than a different figure (unless Habbo can't be reached)
	if not AV.renderer or not figureReady(figure) then return not AV.failed end
	local e = imageFor(u, figure)
	local key = stateKey(info)
	if e.state ~= key then
		e.state = key
		NA.setState(e.image, {
			direction = info.dir, headDirection = info.dir, posture = info.posture, postureParameter = "",
			gesture = 0, dance = 0, sign = -1, carryObject = 0, useObject = 0,
			talk = false, sleep = false, blink = false, expression = 0, effect = 0,
		})
		e.frame = nil
		e.forced = FRAME_EVERY
	end
	-- Nitro: animate while the avatar is animating (and a few updates after a change)
	if info.now - e.lastUpdate >= UPDATE then
		e.lastUpdate = info.now
		if NA.isAnimating(e.image) or (e.forced or 0) > 0 then
			e.forced = (e.forced or 0) - 1
			e.updates = e.updates - 1
			if e.updates <= 0 then
				NA.next(e.image)
				e.updates = FRAME_EVERY
				e.frame = nil
			end
		end
	end
	e.frame = e.frame or NA.frame(e.image)
	local f = e.frame
	if f.width == 0 then return false end
	local k = info.k
	local co = f.canvasOffsets
	local cx, cy, cz = 0, 0, 0
	if co and co[3] then cx, cy, cz = co[1], co[2], co[3] end
	local postureOffset = (info.posture == "sit" or info.posture == "lay") and ROOM_SCALE / 2 or 0
	-- AvatarVisualization: the avatar picture's corner relative to the spot it stands on
	local ox = ((-ROOM_SCALE / 2) + cx) - ((f.width - ROOM_SCALE) / 2)
	local oy = ((-f.height + (ROOM_SCALE / 4)) + cy) + postureOffset
	-- the avatar's corner on screen, on a whole pixel
	local bx, by = math.floor(info.sx + 0.5), math.floor(info.sy + 0.5)
	-- pixel art: no blurring between pixels when it is scaled up or down
	render.PushFilterMag(TEXFILTER.POINT)
	render.PushFilterMin(TEXFILTER.POINT)
	-- the shadow (std/mv): Habbo's h_std_sd_1_0_0 at (-17, -7), at alpha 50
	if info.posture == "mv" or info.posture == "std" then
		sprite("h_std_sd_1_0_0", bx, by, -17, -7, k, false, 0xFFFFFF, 50)
	end
	for _, s in ipairs(f.sprites) do
		sprite(s.name, bx, by, ox + s.x, oy + s.y, k, s.flipH, s.color)
	end
	render.PopFilterMin()
	render.PopFilterMag()
	return true
end

BOBBA.room = BOBBA.room or { units = {} }
BOBBA.room.figureDrawer = draw

-- get everything ready as the game starts, so people show up with the room
function H.preloadAvatars(figures)
	renderer(function()
		for _, figure in ipairs(figures or { H.DEFAULT_FIGURE }) do figureReady(figure) end
	end)
end
-- now: while the game loads (from the files saved last time this needs no internet)
H.preloadAvatars()
