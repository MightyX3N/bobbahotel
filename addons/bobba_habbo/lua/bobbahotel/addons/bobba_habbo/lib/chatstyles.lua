-- Habbo's chat bubbles: the pictures and measurements of every bubble style, from HabboAir.swf in
-- Habbo's desktop client (the same download as the avatar data). In the SWF the pictures and text
-- files are embedded classes with made-up names (chat_bubble_base_png$d550...); which asset name
-- each one has (style_normal_chat_bubble_base) is only written in the ActionScript, as
-- "Class.style_normal_chat_bubble_base = chat_bubble_base_png$d550...", so that code is read (its
-- ABC bytecode) to find the pairs. The pictures are PNG files inside DefineBitsJPEG2 tags; they are
-- saved padded to a power-of-two size, like every other Habbo picture here.
--
--   H.chatStyles(function(styles, err) ... end)
--     styles[id] = { id, asset = "normal", system = true/false, base = img, color = img (or nil),
--                    pointer = img, reg = { ["9sliceXY"] = "29,17", ... } }
--     img = { path, width, height, texWidth, texHeight }
--   (id: Habbo's chat style number; 0 is the normal bubble everyone has)
--   styles.images[name] = img   the other pictures (H.CLIENT_IMAGES), by their name in Habbo's client

local H = BOBBA.habbo
local P = BOBBA.platform

H.CHAT_INDEX_VERSION = "10"

-- other pictures of Habbo's client the hotel draws with (saved in the same pass): the avatar editor's
-- icons ("_off" is how Habbo shows one that isn't chosen)
H.CLIENT_IMAGES = {}
for _, n in ipairs({ "gender_male", "gender_female", "head_hair", "head_hats", "head_accessories", "head_eyewear",
	"head_face_accessories", "top_shirt", "top_prints", "top_jacket", "top_accessories", "bottom_trousers",
	"bottom_shoes", "bottom_accessories" }) do
	H.CLIENT_IMAGES[#H.CLIENT_IMAGES + 1] = "avatar_editor_tabs_" .. n
	H.CLIENT_IMAGES[#H.CLIENT_IMAGES + 1] = "avatar_editor_tabs_" .. n .. "_off"
end
for _, n in ipairs({ "avatar_editor_generic_remove_selection", "avatar_editor_rotate_avatar_button", "avatar_editor_generic_platform" }) do
	H.CLIENT_IMAGES[#H.CLIENT_IMAGES + 1] = n
end
-- ... the toolbar, the "me" menu, the purse, the room tools, the friend bar and the navigator (ui.lua
-- says which is which)
for _, n in ipairs({ "bottom_bar_logo", "bottom_bar_home", "bottom_bar_navigator", "bottom_bar_shop", "bottom_bar_inventory",
	"bottom_bar_camera", "bottom_bar_games", "friend_bar_all_friends", "friend_bar_friendlist_messenger",
	"friend_bar_friendlist_messenger_notify_1", "find_friends_icon_png", "friend_bar_friendlist_chat",
	"friend_bar_friendlist_go_room", "friend_bar_search_habbos", "me_menu_me_achv", "me_menu_me_profile",
	"me_menu_me_rooms", "me_menu_me_clothing", "me_menu_me_guide", "me_menu_me_talents", "me_menu_me_forums",
	"pursearea_credits_icon", "pursearea_duckets_icon", "pursearea_diamond_icon", "pursearea_hc_icon", "help_guide_icon",
	"roomtools_gear", "roomtools_magnifier", "roomtools_chat_history", "roomtools_like", "roomtools_history_open_icon",
	"common_chat_styles", "home_png", "navigation_icon_weblink",
	"newnavigator_button_show_room_info", "newnavigator_icon_group", "newnavigator_doormode_password_small",
	"newnavigator_doormode_doorbell_small", "newnavigator_doormode_invisible_small", "newnavigator_roominfo_temp",
	"newnavigator_create_room", "newnavigator_default_room", "newnavigator_icon_usercount", "newnavigator_button_tiles",
	"newnavigator_button_rows", "newnavigator_button_category_collapse", "newnavigator_button_category_expand",
	"newnavigator_button_category_show_more", "newnavigator_random_room", "newnavigator_refresh_search_icon",
	"newnavigator_icon_fav_no", "newnavigator_icon_fav_yes", "newnavigator_icon_home_no", "newnavigator_icon_home_yes",
	"newnavigator_room_settings_icon", "newnavigator_event_icon", "icons_tickmark", "icons_back", "icons_next",
	"messenger_caution", "messenger_notification_icon", "ask_for_friend_png", "follow_friend_png",
	"relationship_status_heart", "relationship_status_smile", "relationship_status_bobba", "small_pen",
	"inventory_inventory_empty", "talent_vip_reward", "vip_color", "trophy_bg_gold", "trophy_bg_silver", "trophy_bg_bronze", "catalogue_giftcard_blank",
	"stickie_blanco", "stickie_close", "stickie_remove", "dimmer_info",
	-- the floor plan editor
	"floor_plan_editor_add_tile", "floor_plan_editor_remove_tile", "floor_plan_editor_raise_tile", "floor_plan_editor_sink_tile",
	"floor_plan_editor_enter_tile", "floor_editor_tile_base", "floor_editor_tile_entry", "floor_editor_tile_base_large",
	"floor_editor_tile_entry_large", "enterdirection_ghost_avatar", "enterdirection_left", "enterdirection_right",
	"floor_plan_editor_logo", "floor_plan_editor_button" }) do
	H.CLIENT_IMAGES[#H.CLIENT_IMAGES + 1] = n
end
-- ... and Habbo's sounds (MP3s in the client; nitro-react's SoundNames, sounds.url): money in, a
-- message, respect, the camera, help
H.CLIENT_SOUNDS = { "sound_catalogue_cash", "sound_catalogue_duckets", "sound_console_message_sent", "sound_console_new_message",
	"sound_respect_received", "sound_camera_shutter", "sound_call_for_help", "sound_guide_received_invitation", "sound_guide_help_requested" }
-- pictures cut out of a bigger one: the "me" menu's settings cog is the cog of settings_color, without
-- the horn in front of it (mask: per row, the runs of pixels kept, the shape nitro-react's cog has)
H.CLIENT_IMAGE_CROPS = { settings_color_cog = { from = "settings_color", x = 18, y = 6, w = 28, h = 34,
	mask = "13-14 6-8,11-16 4-18 4-18 3-18 3-18 4-18,22-24 4-18,20-24 3-25 1-25 0-26 0-26 0-25 0-24 0-12,14-23 1-12,15-23 "
		.. "3-13,15-23 4-13,16-25 4-14,16-27 4-27 3-27 2-27 2-27 3-26 3-26 4-23 4-6,9-24 9-24 9-24 9-24 9-24 10-23 12-14,18-21 18-19" } }
-- and grey copies (CSS's filter: grayscale(1), as the "me" menu shows its icons until hovered)
H.CLIENT_IMAGE_GRAY = { me_menu_me_achv = true, me_menu_me_profile = true, me_menu_me_rooms = true,
	me_menu_me_clothing = true, me_menu_me_guide = true, me_menu_me_talents = true, settings_color_cog = true }

local byte, sub, find = string.byte, string.sub, string.find

-- { width, height, pixels = { r, g, b, a, ... } } pictures: a piece of one, and a grey copy (CSS's
-- grayscale(1): each pixel's luminance, 0.2126 R + 0.7152 G + 0.0722 B)
function H.cropImage(img, x, y, w, h, mask)
	local keep
	if mask then
		keep = {}
		local r = 0
		for row in mask:gmatch("%S+") do
			local set = {}
			for a, b in row:gmatch("(%d+)%-(%d+)") do for c = tonumber(a), tonumber(b) do set[c] = true end end
			keep[r] = set
			r = r + 1
		end
	end
	local out, n = {}, 0
	for row = y, y + h - 1 do
		for col = x, x + w - 1 do
			local i = (row * img.width + col) * 4
			local inside = row >= 0 and col >= 0 and row < img.height and col < img.width
			if keep and not (keep[row - y] and keep[row - y][col - x]) then inside = false end
			for k = 1, 4 do n = n + 1 out[n] = inside and img.pixels[i + k] or 0 end
		end
	end
	return { width = w, height = h, pixels = out }
end

function H.grayImage(img)
	local src, out = img.pixels, {}
	for i = 1, #src, 4 do
		local l = math.floor(0.2126 * src[i] + 0.7152 * src[i + 1] + 0.0722 * src[i + 2] + 0.5)
		out[i], out[i + 1], out[i + 2], out[i + 3] = l, l, l, src[i + 3]
	end
	return { width = img.width, height = img.height, pixels = out }
end

local function indexPath(version) return H.cachePath("chat/client_" .. version .. "/styles", ".txt") end
local function imagePath(version, name) return H.cachePath("chat/client_" .. version .. "/" .. name, ".png") end

-- --- ActionScript bytecode: which embedded class each asset name is ----------------------------------
-- Reads an ABC block (avm2overview.pdf, "abcFile") up to its method bodies, and looks in their code
-- for: getlex <Class>, findproperty <field>, swap, setproperty <field>. Returns { field = className }.
local function abcAssets(b, out)
	local p = 5 -- after minor and major version
	local function u30()
		local r, s = 0, 0
		for _ = 1, 5 do
			local c = byte(b, p)
			p = p + 1
			r = r + (c % 128) * 2 ^ s
			s = s + 7
			if c < 128 then break end
		end
		return r
	end
	local function u8() p = p + 1 return byte(b, p - 1) end
	local function skip(n) for _ = 1, n do u30() end end
	local n = u30() skip(math.max(0, n - 1))           -- ints
	n = u30() skip(math.max(0, n - 1))                 -- uints
	n = u30() p = p + 8 * math.max(0, n - 1)           -- doubles
	n = u30()
	local strings = { [0] = "" }
	for i = 1, n - 1 do
		local l = u30()
		strings[i] = sub(b, p, p + l - 1)
		p = p + l
		if i % 2000 == 0 then H.yield() end
	end
	n = u30()                                          -- namespaces
	for _ = 1, n - 1 do u8() u30() end
	n = u30()                                          -- namespace sets
	for _ = 1, n - 1 do skip(u30()) end
	n = u30()                                          -- multinames
	local names = {}
	for i = 1, n - 1 do
		local k = u8()
		if k == 0x07 or k == 0x0D then u30() names[i] = strings[u30()]
		elseif k == 0x0F or k == 0x10 then names[i] = strings[u30()]
		elseif k == 0x11 or k == 0x12 then names[i] = false
		elseif k == 0x09 or k == 0x0E then names[i] = strings[u30()] u30()
		elseif k == 0x1B or k == 0x1C then u30() names[i] = false
		elseif k == 0x1D then u30() skip(u30()) names[i] = false
		else return nil, "unknown multiname kind " .. k end
	end
	H.yield()
	n = u30()                                          -- methods
	for _ = 1, n do
		local params = u30()
		u30() skip(params) u30()
		local flags = u8()
		if bit.band(flags, 0x08) ~= 0 then for _ = 1, u30() do u30() u8() end end
		if bit.band(flags, 0x80) ~= 0 then skip(params) end
	end
	n = u30()                                          -- metadata
	for _ = 1, n do u30() skip(u30() * 2) end
	local function traits()
		for _ = 1, u30() do
			u30()
			local k = u8()
			local kind = k % 16
			if kind == 0 or kind == 6 then
				u30() u30()
				if u30() ~= 0 then u8() end
			else
				u30() u30()
			end
			if bit.band(k, 0x40) ~= 0 then skip(u30()) end
		end
	end
	local classes = u30()
	for _ = 1, classes do                              -- instances
		u30() u30()
		local flags = u8()
		if bit.band(flags, 0x08) ~= 0 then u30() end
		skip(u30())
		u30()
		traits()
	end
	for _ = 1, classes do u30() traits() end           -- classes
	for _ = 1, u30() do u30() traits() end             -- scripts
	H.yield()
	for body = 1, u30() do                             -- method bodies
		skip(5)
		local len = u30()
		local code = sub(b, p, p + len - 1)
		p = p + len
		for _ = 1, u30() do skip(5) end
		traits()
		local function rd(j)
			local v, s = 0, 0
			while true do
				local c = byte(code, j)
				if not c then return nil, j end
				j = j + 1
				v = v + (c % 128) * 2 ^ s
				s = s + 7
				if c < 128 then return v, j end
			end
		end
		local i = 1
		while true do
			i = find(code, "\96", i, true)
			if not i then break end
			local y, j = rd(i + 1)
			if y and byte(code, j) == 0x5E then
				local x, k = rd(j + 1)
				if x and byte(code, k) == 0x2B and byte(code, k + 1) == 0x61 then
					local x2 = rd(k + 2)
					if x2 == x and names[x] and names[y] then out[names[x]] = names[y] end
				end
			end
			i = i + 1
		end
		if body % 200 == 0 then H.yield() end
	end
	return out
end

-- --- HabboAir.swf -> the styles' files in the cache ----------------------------------------------------
local function readTags(s)
	-- after the header: the stage size (a RECT: 5 bits saying how many bits each of its 4 numbers has)
	local nbits = math.floor(byte(s, 9) / 8)
	local p = 9 + math.ceil((5 + nbits * 4) / 8) + 4
	local symbols, tags, abcs = {}, {}, {}
	while p + 1 <= #s do
		local head = byte(s, p) + byte(s, p + 1) * 256
		p = p + 2
		local code, len = math.floor(head / 64), head % 64
		if len == 63 then
			local a, b2, c, d = byte(s, p, p + 3)
			len = a + b2 * 256 + c * 65536 + d * 16777216
			p = p + 4
		end
		if code == 0 then break end
		if code == 76 then -- SymbolClass: id -> class name
			local q = p
			local count = byte(s, q) + byte(s, q + 1) * 256
			q = q + 2
			for _ = 1, count do
				local id = byte(s, q) + byte(s, q + 1) * 256
				local e = find(s, "\0", q + 2, true)
				local name = sub(s, q + 2, e - 1)
				symbols[name] = id
				-- (classes in a package: also by the name after the last dot)
				symbols[name:match("([^%.]+)$")] = symbols[name:match("([^%.]+)$")] or id
				q = e + 1
			end
		elseif code == 87 or code == 21 then -- DefineBinaryData, DefineBitsJPEG2 (here: PNG files)
			local id = byte(s, p) + byte(s, p + 1) * 256
			tags[id] = { start = p + (code == 87 and 6 or 2), stop = p + len - 1 }
		elseif code == 14 and math.floor(byte(s, p + 2) / 16) == 2 then -- DefineSound, MP3: after id, format, count, seek
			local id = byte(s, p) + byte(s, p + 1) * 256
			tags[id] = { start = p + 9, stop = p + len - 1 }
		elseif code == 82 then -- DoABC: flags, a name, the bytecode
			local e = find(s, "\0", p + 4, true)
			abcs[#abcs + 1] = sub(s, e + 1, p + len - 1)
		end
		p = p + len
	end
	return symbols, tags, abcs
end

-- the bubble styles out of HabboAir.swf (its bytes as in the ZIP), into the cache. true or nil, why
function H.saveChatStyles(swfBytes, version)
	local s, why = H.swf.uncompress(swfBytes, H.inflate)
	if not s then return nil, why end
	H.yield()
	local symbols, tags, abcs = readTags(s)
	local assets = {}
	for _, abc in ipairs(abcs) do
		local ok, err = abcAssets(abc, assets)
		if not ok then return nil, "HabboAir.swf's code: " .. tostring(err) end
	end
	local function bytesOf(asset)
		local cls = assets[asset]
		local id = cls and symbols[cls]
		local t = id and tags[id]
		return t and sub(s, t.start, t.stop)
	end
	local xml = bytesOf("chatstyles_xml")
	if not xml then return nil, "HabboAir.swf has no chat styles" end
	local lines = { H.CHAT_INDEX_VERSION }
	local saved = 0
	for attrs in xml:gmatch("<style%s+([^>]-)/?>") do
		local id = tonumber(attrs:match('id="(%d+)"'))
		local asset = attrs:match('assetId="([^"]+)"')
		if id and asset then
			local reg = bytesOf("style_" .. asset .. "_regpoints")
			if reg then
				lines[#lines + 1] = table.concat({ "S", id, asset, attrs:match('systemStyle="true"') and 1 or 0 }, "\t")
				for k, v in reg:gmatch("([%w]+)%s*=%s*([^\r\n]*)") do
					lines[#lines + 1] = table.concat({ "R", id, k, (v:gsub("%s+$", "")) }, "\t")
				end
				for _, part in ipairs({ "base", "color", "pointer" }) do
					local png = bytesOf("style_" .. asset .. "_chat_bubble_" .. part)
					if png then
						local img, why2 = H.png.decode(png, H.inflate)
						if not img then return nil, "style_" .. asset .. "_chat_bubble_" .. part .. ": " .. tostring(why2) end
						local path = imagePath(version, asset .. "_" .. part)
						local px, tw, th = H.paddedPixels(img)
						P.writeData(path, H.png.encode(tw, th, px, H.zlib))
						lines[#lines + 1] = table.concat({ "I", id, part, path, img.width, img.height, tw, th }, "\t")
						saved = saved + 1
						H.yield()
					end
				end
			end
		end
	end
	if saved == 0 then return nil, "HabboAir.swf's chat styles have no pictures" end
	local function save(name, img)
		local path = imagePath(version, "ui_" .. name)
		local px, tw, th = H.paddedPixels(img)
		P.writeData(path, H.png.encode(tw, th, px, H.zlib))
		lines[#lines + 1] = table.concat({ "U", name, path, img.width, img.height, tw, th }, "\t")
		if H.CLIENT_IMAGE_GRAY[name] then
			local g = H.grayImage(img)
			local gpath = imagePath(version, "ui_" .. name .. "_gray")
			local gpx, gtw, gth = H.paddedPixels(g)
			P.writeData(gpath, H.png.encode(gtw, gth, gpx, H.zlib))
			lines[#lines + 1] = table.concat({ "U", name .. "_gray", gpath, g.width, g.height, gtw, gth }, "\t")
		end
		H.yield()
	end
	local decoded = {}
	local function decode(name)
		if decoded[name] == nil then
			local png = bytesOf(name)
			decoded[name] = png and H.png.decode(png, H.inflate) or false
		end
		return decoded[name] or nil
	end
	for _, name in ipairs(H.CLIENT_IMAGES) do
		local img = decode(name)
		if img then save(name, img) end
	end
	for name, c in pairs(H.CLIENT_IMAGE_CROPS) do
		local img = decode(c.from)
		if img then save(name, H.cropImage(img, c.x, c.y, c.w, c.h, c.mask)) end
	end
	for _, name in ipairs(H.CLIENT_SOUNDS) do
		local mp3 = bytesOf(name)
		if mp3 then
			local path = H.cachePath("chat/client_" .. version .. "/" .. name, ".mp3")
			P.writeData(path, mp3)
			lines[#lines + 1] = table.concat({ "A", name, path }, "\t")
		end
	end
	P.writeData(indexPath(version), table.concat(lines, "\n") .. "\n")
	return true
end

local function readIndex(version)
	local path = indexPath(version)
	if not P.dataExists(path) then return nil end
	local text = P.readData(path)
	if not text or text:match("^([^\n]*)") ~= H.CHAT_INDEX_VERSION then return nil end
	local styles = { images = {}, sounds = {} }
	for line in text:gmatch("[^\n]+") do
		local f = {}
		for v in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = v end
		local id = tonumber(f[2])
		if f[1] == "U" then
			if not P.dataExists(f[3]) then return nil end
			styles.images[f[2]] = { path = f[3], width = tonumber(f[4]), height = tonumber(f[5]), texWidth = tonumber(f[6]), texHeight = tonumber(f[7]) }
		elseif f[1] == "A" then
			-- (a sound that couldn't be saved is just left out)
			if P.dataExists(f[3]) then styles.sounds[f[2]] = f[3] end
		elseif f[1] == "S" then
			styles[id] = { id = id, asset = f[3], system = f[4] == "1", reg = {} }
		elseif f[1] == "R" and styles[id] then
			styles[id].reg[f[3]] = f[4]
		elseif f[1] == "I" and styles[id] then
			if not P.dataExists(f[4]) then return nil end
			styles[id][f[3]] = { path = f[4], width = tonumber(f[5]), height = tonumber(f[6]), texWidth = tonumber(f[7]), texHeight = tonumber(f[8]) }
		end
	end
	return styles
end

local cache, waiting
function H.chatStyles(cb)
	if cache then cb(cache) return end
	if waiting then waiting[#waiting + 1] = cb return end
	waiting = { cb }
	local function done(styles, err)
		local list = waiting
		waiting = nil
		cache = styles
		for _, w in ipairs(list) do w(styles, err) end
	end
	H.clientVersion(function(version, url, err)
		if not version then done(nil, err) return end
		local styles = readIndex(version)
		if styles then done(styles) return end
		H.habboAir(function(swfBytes, _, err2)
			if not swfBytes then done(nil, err2) return end
			H.work(function()
				local ok, why2 = H.saveChatStyles(swfBytes, version)
				swfBytes = nil
				collectgarbage()
				if not ok then done(nil, why2) return end
				done(readIndex(version))
			end, true)
		end)
	end)
end
