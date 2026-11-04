-- Habbo in the hotel's UI (client): the pictures the toolbar, purse, room tools, "me" menu and windows
-- draw (BOBBA.ui.iconProvider, by nitro-react's names for them; Habbo's own pictures out of its
-- client, HabboAir.swf, matched to Nitro's pixel for pixel where Nitro copied them), and Habbo's
-- texts for everything (external_flash_texts, all of it).

local H = BOBBA.habbo
local P = BOBBA.platform
-- (addons load before the gamemode's client files: the table is started here if it isn't there yet)
BOBBA.ui = BOBBA.ui or { windows = {} }
local U = BOBBA.ui

-- nitro-react's name -> the picture in HabboAir.swf
H.UI_ICONS = {
	habbo = "bottom_bar_logo", house = "bottom_bar_home", rooms = "bottom_bar_navigator", catalog = "bottom_bar_shop",
	inventory = "bottom_bar_inventory", camera = "bottom_bar_camera", game = "bottom_bar_games",
	friendall = "friend_bar_all_friends", message = "friend_bar_friendlist_messenger",
	["message-unseen"] = "friend_bar_friendlist_messenger_notify_1", ["friend-search"] = "find_friends_icon_png",
	["friendbar-chat"] = "friend_bar_friendlist_chat", ["friendbar-visit"] = "friend_bar_friendlist_go_room",
	["me-achievements"] = "me_menu_me_achv", ["me-profile"] = "me_menu_me_profile", ["me-rooms"] = "me_menu_me_rooms",
	["me-clothing"] = "me_menu_me_clothing", ["me-settings"] = "settings_color_cog", ["me-helper-tool"] = "me_menu_me_guide",
	["me-talents"] = "me_menu_me_talents", ["me-forums"] = "me_menu_me_forums",
	["currency-credits"] = "pursearea_credits_icon", ["currency-duckets"] = "pursearea_duckets_icon",
	["currency-diamonds"] = "pursearea_diamond_icon", ["currency-hc"] = "pursearea_hc_icon",
	help = "help_guide_icon", ["purse-cog"] = "roomtools_gear",
	["room-settings"] = "roomtools_gear", ["room-zoom"] = "roomtools_magnifier", ["room-chat-history"] = "roomtools_chat_history",
	["room-like"] = "roomtools_like", ["small-room"] = "roomtools_history_open_icon", ["room-link"] = "navigation_icon_weblink",
	["chat-styles"] = "common_chat_styles", ["house-small"] = "home_png",
	["nav-info"] = "newnavigator_button_show_room_info", ["nav-group"] = "newnavigator_icon_group",
	["nav-password"] = "newnavigator_doormode_password_small", ["nav-locked"] = "newnavigator_doormode_doorbell_small",
	["nav-invisible"] = "newnavigator_doormode_invisible_small", ["nav-thumbnail"] = "newnavigator_roominfo_temp",
	["nav-create"] = "newnavigator_create_room", ["nav-default-room"] = "newnavigator_default_room",
	["nav-usercount"] = "newnavigator_icon_usercount", ["nav-tiles"] = "newnavigator_button_tiles", ["nav-rows"] = "newnavigator_button_rows",
	["nav-collapse"] = "newnavigator_button_category_collapse", ["nav-expand"] = "newnavigator_button_category_expand",
	["nav-show-more"] = "newnavigator_button_category_show_more", ["nav-random"] = "newnavigator_random_room",
	["nav-refresh"] = "newnavigator_refresh_search_icon", ["nav-fav-no"] = "newnavigator_icon_fav_no",
	["nav-fav-yes"] = "newnavigator_icon_fav_yes", ["nav-home-no"] = "newnavigator_icon_home_no",
	["nav-home-yes"] = "newnavigator_icon_home_yes", ["nav-room-settings"] = "newnavigator_room_settings_icon",
	["nav-event"] = "newnavigator_event_icon", tick = "icons_tickmark", back = "icons_back", next = "icons_next",
	["friends-warning"] = "messenger_caution", ["messenger-notification"] = "messenger_notification_icon",
	["friends-add"] = "ask_for_friend_png", ["friends-follow"] = "follow_friend_png", ["friends-heart"] = "relationship_status_heart",
	["friends-smile"] = "relationship_status_smile", ["friends-bobba"] = "relationship_status_bobba", pencil = "small_pen",
	["inventory-empty"] = "inventory_inventory_empty", ["hc-banner"] = "talent_vip_reward",
	["vip-banner"] = "vip_color", ["currency-vip"] = "vip_color",
	["trophy-1"] = "trophy_bg_gold", ["trophy-2"] = "trophy_bg_silver", ["trophy-3"] = "trophy_bg_bronze", ["gift-card"] = "catalogue_giftcard_blank",
	["fp-set"] = "floor_plan_editor_add_tile", ["fp-unset"] = "floor_plan_editor_remove_tile", ["fp-up"] = "floor_plan_editor_raise_tile",
	["fp-down"] = "floor_plan_editor_sink_tile", ["fp-door"] = "floor_plan_editor_enter_tile", ["fp-tile"] = "floor_editor_tile_base_large",
	["fp-entry"] = "floor_editor_tile_entry_large",
	["stickie"] = "stickie_blanco", ["stickie-close"] = "stickie_close", ["stickie-trash"] = "stickie_remove", ["dimmer-banner"] = "dimmer_info",
}

local images, failed
local function clientImages()
	if images then return images end
	H.chatStyles(function(st) if st then images = st.images else failed = true end end)
	return images
end
H.clientImages = clientImages

-- Habbo's sounds for the hotel's (BOBBA.sounds, the gamemode's client/sounds.lua): nitro-react's names
local SOUNDS = { credits = "sound_catalogue_cash", duckets = "sound_catalogue_duckets", messenger_message_received = "sound_console_new_message",
	messenger_new_thread = "sound_console_message_sent", respect = "sound_respect_received", camera_shutter = "sound_camera_shutter",
	modtools_new_ticket = "sound_call_for_help" }
local sounds
BOBBA.sounds = BOBBA.sounds or {}
BOBBA.sounds.find = function(name)
	if not sounds then H.chatStyles(function(st) if st then sounds = st.sounds or {} end end) end
	return sounds and sounds[SOUNDS[name] or name] or nil
end

-- the hotel's loading screen waits for these pictures, so the toolbar and purse aren't drawn without
-- them for a moment after coming in (unless they can't be had)
H.loadingCheck("habbo.ui", function()
	clientImages()
	return images ~= nil or failed == true, images and 1 or 0
end)

local materials = {}
U.iconProvider = function(name)
	local imgs = clientImages()
	if not imgs then return nil end
	local gray = name:match(":gray$")
	local base = gray and name:sub(1, -6) or name
	local asset = H.UI_ICONS[base] or base
	local img = imgs[asset .. (gray and "_gray" or "")]
	if not img then return nil end
	local m = materials[img.path]
	if not m then
		m = { material = P.dataMaterial(img.path, "noclamp"), width = img.width, height = img.height,
			u = img.width / img.texWidth, v = img.height / img.texHeight }
		materials[img.path] = m
	end
	return m
end

-- --- Habbo's texts -----------------------------------------------------------------------------------
-- (external_flash_texts: key=value lines, about 54,000 of them; the settings name it twice, the last
-- one counts). All of it, a few hundred lines a frame in a job that can wait.
function H.loadAllTexts(done)
	H.config(function(cfg)
		if not cfg then return end
		local url
		for u in cfg.settings:gmatch("\nexternal%.texts%.txt=([^\r\n]*)") do url = u end
		if not url or url:find("${", 1, true) then return end
		H.remembered("texts", url:gsub("^http:", "https:"), function(text)
			if not text then return end
			H.work(function()
				local strings, n = {}, 0
				for k, v in text:gmatch("([%w%._%-]+)=([^\r\n]*)") do
					strings[k] = v
					n = n + 1
					if n % 500 == 0 then H.yield() end
				end
				BOBBA.lang.add("en", strings)
				if done then done(n) end
			end, true)
		end)
	end)
end

-- a few seconds after the game has loaded (so it never holds up the room)
if P.after then P.after(5, function() H.loadAllTexts() clientImages() end) end
