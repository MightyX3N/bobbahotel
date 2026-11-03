-- Habbo's hotel view: the pictures Habbo's settings name (landing.view.background_gradient.uri,
-- background_hotel_top, background_left, background_right), downloaded once into
-- garrysmod/data/bobbahotel/habbo/reception/ and given to the hotel view (client/hotelview.lua).

local H = BOBBA.habbo
local P = BOBBA.platform
local HV = BOBBA.hotelView or {}
BOBBA.hotelView = HV

local KEYS = { background = "landing.view.background_gradient.uri", top = "landing.view.background_hotel_top.uri",
	left = "landing.view.background_left.uri", right = "landing.view.background_right.uri" }

local layers, started = {}, false

local function load(cfg)
	local function get(k) return cfg.settings:match("\n" .. k:gsub("%.", "%%.") .. "=([^\r\n]*)") end
	local lib = get("image.library.url") or "//images.habbo.com/c_images/"
	for name, key in pairs(KEYS) do
		local url = get(key)
		if url and url ~= "" then
			url = url:gsub("%${image%.library%.url}", lib)
			if url:sub(1, 2) == "//" then url = "https:" .. url end
			local file = url:match("([^/?]+)%.png") or name
			local path = "habbo/reception/" .. file:gsub("[^%w_%-]", "_") .. ".png"
			local function use()
				local m = P.dataMaterial(path, "noclamp smooth")
				if m and not m:IsError() then layers[name] = { material = m, width = m:Width(), height = m:Height() } end
			end
			if P.dataExists(path) then use()
			else
				H.httpGet(url, function(body)
					if body:sub(2, 4) ~= "PNG" then return end
					P.writeData(path, body)
					use()
				end, function(why) print("[Bobba] Habbo's hotel view: " .. tostring(why)) end, true)
			end
		end
	end
end

-- (the gradient's colour at its bottom fills the rest of the sky: Habbo's #6eadc8-ish blue)
HV.provider = function()
	if not started then
		started = true
		H.config(function(cfg) if cfg then load(cfg) end end)
	end
	return layers
end
