-- Habbo in the avatar editor (client): the gamemode's editor (client/avatareditor.lua) gets Habbo's
-- figuredata, draws each piece of clothing the way nitro-react's AvatarEditorGridPartItem makes its
-- thumbnail, the avatar the way LayoutAvatarImageView does (the cropped picture), Habbo's own editor
-- icons (from its desktop client, lib/chatstyles.lua) and Habbo's texts for the editor.

local H = BOBBA.habbo
local P = BOBBA.platform
local NA = BOBBA.nitroAvatar
local AV = H.avatars
BOBBA.avatarEditor = BOBBA.avatarEditor or {}
local AE = BOBBA.avatarEditor

AE.figureData = function(cb) H.figureData(cb) end
AE.defaultFigure = function() return H.DEFAULT_FIGURE end

-- --- clothes pictures (AvatarEditorGridPartItem.renderThumb) -----------------------------------------
-- the first direction Habbo has a picture for, the parts in this order
local THUMB_DIRECTIONS = { 2, 6, 0, 4, 3, 1 }
local DRAW_ORDER = { "li", "lh", "ls", "lc", "bd", "sh", "lg", "ch", "ca", "cc", "cp", "wa", "rh", "rs", "rc", "hd", "fc", "ey", "hr", "hrb", "fa", "ea", "ha", "he", "ri" }
local ORDER = {}
for i, t in ipairs(DRAW_ORDER) do ORDER[t] = i end

local thumbs = {}

local function thumbFor(category, set)
	local figure = category .. "-" .. set.id
	local t = thumbs[figure]
	if t then return t end
	if not AV.renderer then return nil end
	-- (the set's own libraries: "hr-100")
	if not AV.figureReady(figure) then return nil end
	local parts = {}
	for _, p in ipairs(set.parts) do parts[#parts + 1] = p end
	table.sort(parts, function(a, b)
		local ia, ib = ORDER[a.type] or 99, ORDER[b.type] or 99
		if ia ~= ib then return ia < ib end
		return (a.index or 0) < (b.index or 0)
	end)
	local sprites = {}
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(parts) do
		for _, dir in ipairs(THUMB_DIRECTIONS) do
			local name = "h_std_" .. p.type .. "_" .. p.id .. "_" .. dir .. "_0"
			local a = AV.assets[name]
			if a then
				-- Nitro's asset offset is the manifest's, negated
				local x, y = -a.offsetX, -a.offsetY
				sprites[#sprites + 1] = { name = name, x = x, y = y, colorIndex = p.colorIndex or 0 }
				x0, y0 = math.min(x0, x), math.min(y0, y)
				x1, y1 = math.max(x1, x + a.width), math.max(y1, y + a.height)
				break
			end
		end
	end
	t = { sprites = sprites, x0 = x0, y0 = y0, w = x1 - x0, h = y1 - y0 }
	thumbs[figure] = t
	return t
end

-- New pictures are made (H.image) at most about 8 ms a frame here; the rest show "loading" for
-- a frame or two, so a tab full of new clothes doesn't stall the game.
H.EDITOR_IMAGE_BUDGET = 0.008
local budgetFrame, budgetUsed = -1, 0
local function picturesReady(names)
	local frame = FrameNumber and FrameNumber() or 0
	if frame ~= budgetFrame then budgetFrame, budgetUsed = frame, 0 end
	for _, name in ipairs(names) do
		local a = AV.assets[name]
		if a and H.pendingImages[a.path] then
			if budgetUsed >= H.EDITOR_IMAGE_BUDGET then return false end
			local t = SysTime()
			H.image(a.path)
			budgetUsed = budgetUsed + (SysTime() - t)
		end
	end
	return true
end

-- (the picture as an image: the box around what's drawn, in the middle of the cell)
local function drawSprites(t, cx, cy, k, colorOf)
	if #t.sprites == 0 then return end
	local bx = math.floor(cx - t.w * k / 2 - t.x0 * k + 0.5)
	local by = math.floor(cy - t.h * k / 2 - t.y0 * k + 0.5)
	render.PushFilterMag(TEXFILTER.POINT)
	render.PushFilterMin(TEXFILTER.POINT)
	for _, sp in ipairs(t.sprites) do
		AV.sprite(sp.name, bx, by, sp.x, sp.y, k, false, colorOf(sp), sp.alpha)
	end
	render.PopFilterMin()
	render.PopFilterMag()
end

-- an avatar picture (all of it, or the head): its parts and the box around them
local images = {}
local function avatarPicture(figure, gender, direction, head)
	if not AV.renderer or not AV.figureReady(figure) then return nil end
	local key = figure .. "|" .. direction .. (head and "|h" or "")
	local e = images[key]
	if e then return e end
	local image = AV.renderer:createImage(figure, "h")
	NA.setState(image, {
		direction = direction, headDirection = direction, posture = "std", postureParameter = "",
		gesture = 0, dance = 0, sign = -1, carryObject = 0, useObject = 0,
		talk = false, sleep = false, blink = false, expression = 0, effect = 0,
	})
	local f = NA.frame(image, head and true or false)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	local sprites = {}
	for _, s in ipairs(f.sprites) do
		local a = AV.assets[s.name]
		if a then
			sprites[#sprites + 1] = { name = s.name, x = s.x, y = s.y, flip = s.flipH, color = s.color }
			x0, y0 = math.min(x0, s.x), math.min(y0, s.y)
			x1, y1 = math.max(x1, s.x + a.width), math.max(y1, s.y + a.height)
		end
	end
	if #sprites == 0 then return nil end
	-- (cw, ch: the avatar's whole canvas, which is what Nitro's getCroppedImage makes a picture of)
	e = { sprites = sprites, x0 = x0, y0 = y0, w = x1 - x0, h = y1 - y0, cw = f.width, ch = f.height }
	images[key] = e
	return e
end

local function drawPicture(e, x, y, k)
	render.PushFilterMag(TEXFILTER.POINT)
	render.PushFilterMin(TEXFILTER.POINT)
	for _, s in ipairs(e.sprites) do
		AV.sprite(s.name, x, y, s.x - e.x0, s.y - e.y0, k, s.flip, s.color)
	end
	render.PopFilterMin()
	render.PopFilterMag()
end

AE.drawPart = function(category, item, figure, cx, cy, s)
	if category == "hd" then
		-- BodyModel: the face, as the head of a figure with only it (in the figure's skin colour)
		local e = avatarPicture(figure:getFigureStringWithFace(item.id), figure.gender, 2, true)
		if not e then return false end
		if not e.names then
			e.names = {}
			for _, sp in ipairs(e.sprites) do e.names[#e.names + 1] = sp.name end
		end
		if not picturesReady(e.names) then return false end
		drawPicture(e, math.floor(cx - e.w * s / 2 + 0.5), math.floor(cy - e.h * s / 2 + 0.5), s)
		return true
	end
	local t = thumbFor(category, item.partSet)
	if not t then return false end
	if not t.names then
		t.names = {}
		for _, sp in ipairs(t.sprites) do t.names[#t.names + 1] = sp.name end
	end
	if not picturesReady(t.names) then return false end
	drawSprites(t, cx, cy, s, function(sp)
		if item.useColors and sp.colorIndex > 0 then
			local c = item.partColors and item.partColors[sp.colorIndex]
			if c then return c.rgb end
		end
		return 0xFFFFFF
	end)
	return true
end

AE.drawPreview = function(figure, gender, direction, cx, top, k)
	local e = avatarPicture(figure, gender, direction, false)
	if not e then return false end
	-- the canvas in the middle at cx, its top at top
	local x, y = math.floor(cx - e.cw * k / 2 + 0.5), math.floor(top + 0.5)
	render.PushFilterMag(TEXFILTER.POINT)
	render.PushFilterMin(TEXFILTER.POINT)
	for _, s in ipairs(e.sprites) do AV.sprite(s.name, x, y, s.x, s.y, k, s.flip, s.color) end
	render.PopFilterMin()
	render.PopFilterMag()
	return true
end

-- --- Habbo's icons -----------------------------------------------------------------------------------
local ICONS = {
	male = "gender_male", female = "gender_female", hr = "head_hair", ha = "head_hats", he = "head_accessories",
	ea = "head_eyewear", fa = "head_face_accessories", ch = "top_shirt", cp = "top_prints", cc = "top_jacket",
	ca = "top_accessories", lg = "bottom_trousers", sh = "bottom_shoes", wa = "bottom_accessories",
}
local images2
local function clientImages()
	if images2 then return images2 end
	H.chatStyles(function(st) if st then images2 = st.images end end)
	return images2
end

AE.drawIcon = function(name, selected, cx, cy, s)
	local imgs = clientImages()
	if not imgs then return false end
	local asset, flip
	if ICONS[name] then
		asset = "avatar_editor_tabs_" .. ICONS[name] .. (selected and "" or "_off")
	elseif name == "clear" then
		asset = "avatar_editor_generic_remove_selection"
	elseif name == "arrow-left" or name == "arrow-right" then
		asset, flip = "avatar_editor_rotate_avatar_button", name == "arrow-right"
	end
	local img = asset and imgs[asset]
	if not img then return false end
	local w, h = img.width * s, img.height * s
	local x, y = math.floor(cx - w / 2 + 0.5), math.floor(cy - h / 2 + 0.5)
	render.PushFilterMag(TEXFILTER.POINT)
	render.PushFilterMin(TEXFILTER.POINT)
	surface.SetMaterial(AV.material(img.path))
	surface.SetDrawColor(255, 255, 255, 255)
	local u, v = img.width / img.texWidth, img.height / img.texHeight
	if flip then surface.DrawTexturedRectUV(x, y, w, h, u, 0, 0, v) else surface.DrawTexturedRectUV(x, y, w, h, 0, 0, u, v) end
	render.PopFilterMin()
	render.PopFilterMag()
	return true
end

-- --- Habbo's texts for the editor -------------------------------------------------------------------
-- (external_flash_texts: key=value lines; the settings name it twice, the last one counts)
function H.loadTexts(prefixes)
	H.config(function(cfg)
		if not cfg then return end
		local url
		for u in cfg.settings:gmatch("\nexternal%.texts%.txt=([^\r\n]*)") do url = u end
		if not url or url:find("${", 1, true) then return end
		H.remembered("texts", url:gsub("^http:", "https:"), function(text)
			if not text then return end
			local strings = {}
			for k, v in text:gmatch("([%w%._%-]+)=([^\r\n]*)") do
				for _, pre in ipairs(prefixes) do
					if k:sub(1, #pre) == pre then strings[k] = v end
				end
			end
			if next(strings) then BOBBA.lang.add("en", strings) end
		end)
	end)
end

-- --- the editor's clothes, fetched ahead -----------------------------------------------------------
-- Once the room is showing, every clothing file the editor can show (552 sets in about 300 files,
-- a one-time ~30 MB) is downloaded and read in the background, behind everything else, so the
-- editor's tabs are ready when opened. Only what's not saved yet is downloaded.
function H.prefetchClothes()
	H.figureData(function(fd)
		if not fd then return end
		H.avatarData(function(data)
			if not data then return end
			H.config(function(cfg)
				if not cfg then return end
				local seen, names = {}, {}
				for _, t in ipairs({ "hd", "hr", "ha", "he", "ea", "fa", "ch", "cc", "ca", "cp", "lg", "sh", "wa" }) do
					local st = fd.setTypes[t]
					for _, set in ipairs(st and st.sets or {}) do
						if set.selectable and not set.sellable then
							for _, name in ipairs(H.figureLibraryNames(data, t .. "-" .. set.id)) do
								if not seen[name] then seen[name] = true names[#names + 1] = name end
							end
						end
					end
				end
				-- (a job that can wait: the ones read before are skipped, a few each frame)
				H.work(function()
					for i, name in ipairs(names) do
						local key = "figure/" .. name
						if not H.libraryKnown(key) then
							H.library(key, cfg.clientUrl .. name .. ".swf", function() end, { canWait = true })
						end
						if i % 10 == 0 then H.yield() end
					end
				end, true)
			end)
		end)
	end)
end

if BOBBA.events then
	BOBBA.events.on("loadingDone", "bobba_habbo.prefetch", function()
		if P.after then P.after(3, H.prefetchClothes) end
	end)
end

-- a few seconds after the game has loaded (so it never holds up the room), like the chat bubbles
if P.after then P.after(6, function() H.loadTexts({ "avatareditor.", "infostand.button." }) clientImages() end) end
