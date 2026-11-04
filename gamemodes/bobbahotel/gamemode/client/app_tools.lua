-- The tablet's tools: the floor plan editor (client/floorplan.lua's, drawn inside the tablet: a
-- window hosted by the app, see BOBBA.ui.windowHost), and the camera.

local DV = BOBBA.device
local U = BOBBA.ui
local P = BOBBA.platform
local R = BOBBA.room
local V = BOBBA.view
local HUD = BOBBA.hud
local FPE = BOBBA.floorplanEditor
local C, G = DV.C, DV.G
local T = function(k, f, v) return U.text(k, f, v) end

-- the windows an app shows inside the tablet: id -> the app
DV.hosted = DV.hosted or { ["floorplan-editor"] = "floorplan", ["floorplan-io"] = "floorplan" }

-- where a hosted window goes: the app's area (DV.hostRect, set as it draws), the window as big as fits
local nitroHost = U.windowHost
function U.windowHost(id)
	local appId = DV.hosted[id]
	if appId and DV.active() and DV.surface and DV.kind == "tablet" and DV.current() and DV.current().id == appId then
		local surf = DV.surface
		return {
			parent = surf.panel,
			pressed = function() DV.keysAt = SysTime() end,
			place = function()
				local r = DV.hostRect
				local w = U.windows[id]
				if not r or not DV.shown or DV.kind ~= "tablet" or not (DV.current() and DV.current().id == appId) or DV.locked or DV.shade > 0.02 or DV.question or (DV.open or 0) < 0.99 then return nil, nil, 1 end
				local ww, wh = w and w.width or 760, (w and w.height or 500) + 2
				local k = math.min(r.w / ww, r.h / wh)
				local s = (surf.s or 1) * k
				return (r.x + (r.w - ww * k) / 2) * (surf.s or 1), (r.y + (r.h - wh * k) / 2) * (surf.s or 1), s
			end,
		}
	end
	if nitroHost then return nitroHost(id) end
end

-- --- the floor plan editor --------------------------------------------------------------------------
local function floorplanView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	d:rect(0, 0, W, H, Color(236, 239, 246))
	local top = ctx.top + ctx:header(T("floor.plan.editor.title", "Floor Plan Editor"), { big = true })
	DV.hostRect = nil
	if not (V.mode == "room" and R.current) then
		d:text(T("bobba.phone.floorplan.room", "Go to one of your rooms to change its floor plan."), 15, W / 2, top + 80, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		return
	end
	if not U.windows["floorplan-editor"] then
		d:text(ctx.state.error or T("bobba.phone.loading", "Loading…"), 15, W / 2, top + 80, C.ink2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		-- (asked again if it didn't come)
		if SysTime() - (ctx.state.askedAt or 0) > 5 then ctx.state.askedAt = SysTime() P.send("floorplan.get", {}) end
		return
	end
	d:round(24, 24, top + 4, W - 48, H - top - 28, U.C.light)
	DV.hostRect = { x = 32, y = top + 12, w = W - 64, h = H - top - 44 }
end

DV.app({ id = "floorplan", name = T("bobba.phone.app.floorplan", "Floor plan"), color = C.purple, glyph = G.editplan, order = 30,
	description = T("bobba.phone.floorplan.desc", "Change your room's shape"),
	tablet = floorplanView,
	onOpen = function(st) P.send("floorplan.get", {}) end,
	onClose = function()
		DV.hostRect = nil
		for _, id in ipairs({ "floorplan-editor", "floorplan-io" }) do if U.windows[id] then U.windows[id]:close() end end
	end })

-- (the room's info opens it on the tablet in the phone's look)
local openWindow = FPE.open
function FPE.open()
	if DV.active() then DV.openApp("floorplan") return end
	return openWindow()
end
