-- Wired's windows (client; hotel/wired.lua is the server's side), nitro-react's WiredView: a box opened
-- (used) shows its window - primary-slim, 300 wide: its name and what it does, its settings (drawn
-- from the fields the server sends: text, choices, sliders, ticks, a date, a script), the furni chosen
-- ("Click furni in the room to choose them"), an effect's delay, Ready and Cancel. While it's open, a
-- click on furni in the room chooses it or lets it go; the chosen ones are marked.
-- Script boxes get a wider window with the script in a box of its own, and what went wrong last.
-- Also: teleports' Link window (which of your teleports this one takes you to).

BOBBA.wiredUI = BOBBA.wiredUI or {}
local WU = BOBBA.wiredUI
local P = BOBBA.platform
local U = BOBBA.ui
local R = BOBBA.room
local V = BOBBA.view
local T = function(k, f, v) return U.text(k, f, v) end
local BLACK = U.C.black

WU.box = WU.box or nil      -- the box being changed: { id, kind, type, fields, furni, delay, cfg, picked = { id = true }, order = { ids } }

local function info(kind) return R.furniInfo and R.furniInfo(kind) end

-- a time as Nitro's GetWiredTimeLocale: half seconds shown as "1.5"
local function secondsText(v)
	if v == math.floor(v) then return tostring(math.floor(v)) end
	return string.format("%.1f", v)
end

-- is a furni being chosen?
function WU.picking() return WU.box ~= nil and (WU.box.furni or 0) > 0 and U.isOpen("wired") end

-- a furni clicked while choosing: in or out
function WU.pick(it)
	local b = WU.box
	if not b or it.id == b.id then return end
	if b.picked[it.id] then
		b.picked[it.id] = nil
		for i, id in ipairs(b.order) do if id == it.id then table.remove(b.order, i) break end end
	elseif #b.order < b.furni then
		b.picked[it.id] = true
		b.order[#b.order + 1] = it.id
	end
end

-- (nitro-slider: a grey track, a white thumb with a grey ring)
local function slider(w, d, key, x, y, sw, value, min, max, onChange)
	d:round(3, x, y + 7, sw, 6, Color(195, 195, 195))
	local frac = (max > min) and (value - min) / (max - min) or 0
	local tx = x + 8 + (sw - 16) * frac
	d:circle(tx, y + 10, 8, Color(120, 120, 120))
	d:circle(tx, y + 10, 6.5, U.C.white)
	d:click(x, y, sw, 20, function() w.dragging = key end)
	if w.dragging == key then
		if input.IsMouseDown(MOUSE_LEFT) and w.mx then
			local v = min + math.floor(math.Clamp((w.mx - x - 8) / (sw - 16), 0, 1) * (max - min) + 0.5)
			if v ~= value then onChange(v) end
		else
			w.dragging = nil
		end
	end
end

local function hr(d, y, W) d:rect(9, y, W - 18, 1, Color(33, 37, 41)) end

-- a date "YYYY/MM/DD HH:MM" <-> a time (local)
local function dateText(t) return (t and t > 0) and os.date("%Y/%m/%d %H:%M", t) or "" end
local function parseDate(s)
	local y, mo, d, h, mi = tostring(s or ""):match("^%s*(%d%d%d%d)[/%-](%d%d?)[/%-](%d%d?)%s*(%d?%d?):?(%d?%d?)%s*$")
	if not y then return 0 end
	return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h) or 0, min = tonumber(mi) or 0, sec = 0 }) or 0
end

local function drawBox(w, d)
	local b = WU.box
	if not b then w:close() return end
	local W = d.width
	d:slimCard(T("wiredfurni.title", "Wired furni"))
	local fi = info(b.furniKind)
	local y = 31 + 8
	-- what it is
	local kindLabel = ({ trigger = "Trigger", effect = "Effect", condition = "Condition" })[b.kind] or ""
	local tagW = d:textWidth(kindLabel, 10.8, true) + 10
	d:round(3, 9, y, tagW, 16, b.kind == "trigger" and Color(232, 177, 55) or (b.kind == "effect" and Color(60, 140, 200) or Color(120, 180, 90)))
	d:text(kindLabel, 10.8, 9 + tagW / 2, y + 8, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, true)
	local name = (fi and fi.name ~= "" and fi.name) or b.type
	d:text(d:fit(name, 13.5, W - 18 - tagW - 6, true), 13.5, 9 + tagW + 6, y + 8, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
	y = y + 22
	local desc = T("bobba.wired.desc." .. tostring(b.type), b.desc or "")
	if desc ~= "" then
		for _, l in ipairs(d:wrap(desc, 11.5, W - 18)) do d:text(l, 11.5, 9, y, BLACK) y = y + 15 end
	end
	y = y + 4
	local cfg = b.cfg
	-- the settings
	if #b.fields > 0 then
		hr(d, y, W) y = y + 8
		for i, f in ipairs(b.fields) do
			if f.type == "title" then
				d:text(T(f.label, f.fallback), 12.6, 9, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
				y = y + 20
			elseif f.type == "text" then
				d:text(T(f.label, f.fallback), 12.6, 9, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
				y = y + 18
				local e = d:input("text", 9, y, W - 18, 26, { value = cfg.text, max = f.max })
				e.bobbaChange = function(v) cfg.text = v end
				y = y + 32
			elseif f.type == "radio" then
				d:text(T(f.label, f.fallback), 12.6, 9, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
				y = y + 19
				for _, o in ipairs(f.options) do
					local on = (cfg.ints[f.int] or f.options[1][1]) == o[1]
					d:check(9, y, on, true, function() cfg.ints[f.int] = o[1] end)
					d:click(9, y, W - 18, 15, function() cfg.ints[f.int] = o[1] end)
					d:text(d:fit(T(o[2], o[3]), 12.6, W - 40), 12.6, 9 + 20, y + 7.2, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					y = y + 19
				end
				y = y + 4
			elseif f.type == "check" then
				local on = (cfg.ints[f.int] or f.default or 0) == 1
				local function flip() cfg.ints[f.int] = on and 0 or 1 end
				d:check(9, y, on, false, flip)
				d:click(9, y, W - 18, 15, flip)
				d:text(T(f.label, f.fallback), 12.6, 9 + 20, y + 7.2, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				y = y + 20
			elseif f.type == "slider" then
				local v = cfg.ints[f.int] or f.default or f.min
				local label = T(f.label, f.fallback, { seconds = secondsText(v * (f.unit or 1)), value = tostring(v) })
				d:text(label, 12.6, 9, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
				y = y + 18
				slider(w, d, "s" .. i, 9, y, W - 18, v, f.min, f.max, function(nv) cfg.ints[f.int] = nv end)
				y = y + 28
			elseif f.type == "number" then
				d:text(T(f.label, f.fallback), 12.6, 9, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
				y = y + 18
				local e = d:input("n" .. i, 9, y, 100, 26, { value = tostring(cfg.ints[f.int] or f.default or 0), max = 6 })
				e.bobbaChange = function(v) cfg.ints[f.int] = tonumber(v) or 0 end
				y = y + 32
			elseif f.type == "date" then
				d:text(T(f.label, f.fallback), 12.6, 9, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
				y = y + 18
				local e = d:input("d" .. i, 9, y, W - 18, 26, { value = dateText(cfg.ints[f.int]), max = 16, placeholder = "YYYY/MM/DD HH:MM" })
				e.bobbaChange = function(v) cfg.ints[f.int] = parseDate(v) end
				y = y + 32
			end
		end
	end
	-- a script
	if b.script then
		hr(d, y, W) y = y + 8
		d:text(T("bobba.wired.script", "Script (Lua)"), 12.6, 9, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
		d:text(#(cfg.code or "") .. " / 4000", 11, W - 9, y + 1, Color(90, 90, 90), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
		y = y + 18
		local e = d:input("code", 9, y, W - 18, 210, { value = cfg.code or "", max = 4000, multiline = true, size = 11.5,
			placeholder = b.kind == "condition" and "return user ~= nil and user.isOwner" or "say(\"Hello \" .. user.name)" })
		if not e.bobbaTabs then
			e.bobbaTabs = true
			-- (Tab types a tab in the script)
			e.OnKeyCodeTyped = function(self2, code)
				if code == KEY_TAB then
					local pos = self2:GetCaretPos()
					local t = self2:GetValue() or ""
					self2:SetText(t:sub(1, pos) .. "\t" .. t:sub(pos + 1))
					self2:SetCaretPos(pos + 1)
					return true
				end
			end
		end
		e.bobbaChange = function(v) cfg.code = v end
		y = y + 216
		local help = b.kind == "condition"
			and T("bobba.wired.scripthelp.condition", "Return true to let the stack go on. user, trigger, selected, room, memory: see the guide.")
			or T("bobba.wired.scripthelp", "user, trigger, selected (the furni chosen below), room, memory, say(), random(), wait().")
		for _, l in ipairs(d:wrap(help, 11, W - 18)) do d:text(l, 11, 9, y, Color(70, 70, 70)) y = y + 14 end
		if b.scriptsOff then
			d:text(T("bobba.wired.scriptsoff", "Scripts are switched off in this hotel."), 11.5, 9, y, U.C.danger, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
			y = y + 16
		end
		y = y + 4
	end
	-- what went wrong last
	if b.error then
		local lines = d:wrap(T("bobba.wired.lasterror", "Last problem: %error%", { error = b.error }), 11.5, W - 26)
		d:round(4, 9, y, W - 18, #lines * 15 + 8, Color(248, 215, 218))
		for i, l in ipairs(lines) do d:text(l, 11.5, 13, y + 4 + (i - 1) * 15, Color(114, 28, 36)) end
		y = y + #lines * 15 + 14
	end
	-- the furni chosen
	if (b.furni or 0) > 0 then
		hr(d, y, W) y = y + 8
		d:text(T("wiredfurni.pickfurnis.caption", "%count%/%limit% furni selected", { count = #b.order, limit = b.furni }), 12.6, 9, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
		y = y + 18
		for _, l in ipairs(d:wrap(T("wiredfurni.pickfurnis.desc", "To pick a furni, click it in the room. Click it again to unselect it."), 11.5, W - 18)) do
			d:text(l, 11.5, 9, y, BLACK) y = y + 15
		end
		y = y + 4
	end
	-- an effect's delay
	if b.delay then
		hr(d, y, W) y = y + 8
		local v = cfg.delay or 0
		d:text(T("wiredfurni.params.delay", "Delay the effect by %seconds% seconds", { seconds = secondsText(v * 0.5) }), 12.6, 9, y, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, true)
		y = y + 18
		slider(w, d, "delay", 9, y, W - 18, v, 0, 20, function(nv) cfg.delay = nv end)
		y = y + 28
	end
	-- Ready, Cancel
	local bw = (W - 18 - 4) / 2
	d:btn(9, y, bw, 28.9, U.C.success, function() WU.save() end)
	d:text(T("wiredfurni.ready", "Ready"), 12.6, 9 + bw / 2, y + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	d:btn(9 + bw + 4, y, bw, 28.9, U.C.secondary, function() w:close() end)
	d:text(T("cancel", "Cancel"), 12.6, 9 + bw + 4 + bw / 2, y + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	w:setHeight(y + 28.9 + 9)
end

function WU.save()
	local b = WU.box
	if not b then return end
	local ints = {}
	for k, v in pairs(b.cfg.ints) do ints[k] = v end
	P.send("wired.save", { id = b.id, text = b.cfg.text, ints = ints, items = b.order, delay = b.cfg.delay, code = b.cfg.code })
end

P.receive("wired.open", function(_, data)
	local it = R.items[data.id]
	if not it then return end
	if U.windows.wired then U.windows.wired:close() end
	local cfg = data.cfg or {}
	-- (kind: trigger, effect or condition; furniKind: the furni, whose name and description it shows)
	local box = { id = data.id, kind = data.kind, type = data.type, fields = data.fields or {}, furni = tonumber(data.furni) or 0,
		delay = data.delay, script = data.script, error = data.error, scriptsOff = data.scriptsOff, furniKind = it.kind, desc = data.desc,
		cfg = { text = cfg.text or "", ints = {}, delay = tonumber(cfg.delay) or 0, code = cfg.code or "" }, picked = {}, order = {} }
	for i, v in pairs(cfg.ints or {}) do box.cfg.ints[tonumber(i) or i] = tonumber(v) end
	for _, id in ipairs(cfg.items or {}) do box.picked[id] = true box.order[#box.order + 1] = id end
	WU.box = box
	U.window("wired", data.script and 420 or 300, 300, drawBox)
	local w = U.windows.wired
	if w then w.onClose = function() WU.box = nil end end
end)
P.receive("wired.saved", function(_, data)
	if WU.box and WU.box.id == data.id and U.windows.wired then U.windows.wired:close() end
end)
P.receive("wired.error", function(_, data)
	U.alert(T("wiredfurni.title", "Wired furni"), (tostring(data.message or ""):gsub("^%l", string.upper)))
end)

-- the chosen furni: their tiles marked (a blue diamond over each)
R.furniOverlays = R.furniOverlays or {}
R.furniOverlays.wired = function(it, sx, sy, k)
	local b = WU.box
	if not b or not b.picked[it.id] or not U.isOpen("wired") then return nil end
	return function()
		local fi = info(it.kind)
		local w, l = (fi and fi.width) or 1, (fi and fi.length) or 1
		if it.dir == 2 or it.dir == 6 then w, l = l, w end
		local z = it.z or 0
		for tx = it.x, it.x + w - 1 do
			for ty = it.y, it.y + l - 1 do
				local pts = {}
				for _, c in ipairs({ { -0.5, -0.5 }, { 0.5, -0.5 }, { 0.5, 0.5 }, { -0.5, 0.5 } }) do
					local px, py = V.project(tx + c[1], ty + c[2], z)
					if not px then return end
					pts[#pts + 1] = { x = px, y = py }
				end
				surface.SetDrawColor(80, 160, 255, 90)
				draw.NoTexture()
				surface.DrawPoly(pts)
				surface.SetDrawColor(120, 190, 255, 255)
				for i = 1, 4 do
					local a, c2 = pts[i], pts[i % 4 + 1]
					surface.DrawLine(a.x, a.y, c2.x, c2.y)
				end
			end
		end
	end
end

-- --- teleports: the Link window ------------------------------------------------------------------------------
WU.link = WU.link or nil   -- { id, list = tele.links }

local function drawLink(w, d)
	local L = WU.link
	if not L then w:close() return end
	local W = d.width
	d:slimCard(T("bobba.tele.title", "Link teleport"))
	local y = 31 + 8
	for _, l in ipairs(d:wrap(T("bobba.tele.desc", "Choose which of your teleports this one takes you to. Several can lead to the same one."), 12, W - 18)) do
		d:text(l, 12, 9, y, BLACK) y = y + 16
	end
	y = y + 4
	local list = L.list
	if not list then
		d:text(T("generic.loading", "Loading..."), 12.6, 9, y, BLACK)
		w:setHeight(y + 30)
		return
	end
	-- the rows: "No link", then each room's teleports, then those in the inventory
	local rows = { { id = 0, text = T("bobba.tele.none", "Nowhere (you step in and back out)") } }
	for _, room in ipairs(list.rooms or {}) do
		rows[#rows + 1] = { title = room.name }
		for i, t in ipairs(room.teleports or {}) do
			local fi = info(t.kind)
			rows[#rows + 1] = { id = t.id, text = ((fi and fi.name ~= "" and fi.name) or t.kind) .. "  (" .. t.x .. ", " .. t.y .. ")", self = t.id == L.id }
		end
	end
	if #(list.inventory or {}) > 0 then
		rows[#rows + 1] = { title = T("inventory.title", "Inventory") }
		for _, t in ipairs(list.inventory) do
			local fi = info(t.kind)
			rows[#rows + 1] = { id = t.id, text = (fi and fi.name ~= "" and fi.name) or t.kind, self = t.id == L.id }
		end
	end
	local listH = math.min(260, #rows * 22 + 4)
	d:box(9, y, W - 18, listH, 1, 3, U.C.inputBorder, U.C.white)
	local off = d:scroll("tele", 9, y, W - 18, listH, #rows * 22 + 4)
	d:clip(9, y + 1, W - 18, listH - 2, function()
		for i, row in ipairs(rows) do
			local ry = y + 2 + (i - 1) * 22 - off
			if row.title then
				d:text(d:fit(row.title, 12, W - 36, true), 12, 15, ry + 11, Color(60, 60, 60), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
			else
				local on = (list.to or 0) == row.id
				if row.self then
					d:text(d:fit(row.text .. "  " .. T("bobba.tele.this", "(this one)"), 12, W - 50), 12, 33, ry + 11, Color(150, 150, 150), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				else
					d:click(11, ry, W - 22, 22, function() list.to = row.id end)
					if on then d:rect(11, ry, W - 22, 22, U.C.gridActive or Color(220, 235, 245)) end
					d:check(15, ry + 4, on, true, function() list.to = row.id end)
					d:text(d:fit(row.text, 12, W - 60), 12, 35, ry + 11, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end
			end
		end
	end)
	y = y + listH + 8
	local bw = (W - 18 - 4) / 2
	d:btn(9, y, bw, 28.9, U.C.success, function() P.send("tele.link", { id = L.id, to = list.to or 0 }) end)
	d:text(T("bobba.tele.save", "Link"), 12.6, 9 + bw / 2, y + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	d:btn(9 + bw + 4, y, bw, 28.9, U.C.secondary, function() w:close() end)
	d:text(T("cancel", "Cancel"), 12.6, 9 + bw + 4 + bw / 2, y + 14.45, U.C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	w:setHeight(y + 28.9 + 9)
end

function WU.openLink(id)
	WU.link = { id = id }
	if U.windows["tele-link"] then U.windows["tele-link"]:close() WU.link = { id = id } end
	U.window("tele-link", 320, 300, drawLink)
	local w = U.windows["tele-link"]
	if w then w.onClose = function() WU.link = nil end end
	P.send("tele.links", { id = id })
end
P.receive("tele.links", function(_, data)
	if WU.link and WU.link.id == data.from then WU.link.list = data end
end)
P.receive("tele.linked", function(_, data)
	if WU.link and WU.link.id == data.id and U.windows["tele-link"] then U.windows["tele-link"]:close() end
end)

-- is this teleport mine (its Link button)?
function WU.myTeleport(it)
	local fi = info(it.kind)
	if not fi or fi.category ~= "teleport" then return false end
	local me = R.units and R.you and R.units[R.you]
	return me ~= nil and it.owner ~= nil and it.owner == me.key
end
