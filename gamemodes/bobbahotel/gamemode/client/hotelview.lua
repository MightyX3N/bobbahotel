-- The hotel view (client): what you see when you're in no room (nitro-react's HotelView): the sky's
-- colour, the pictures an addon gives (BOBBA.hotelView.provider() -> { color, background, top, left,
-- right }, each { material, width, height }), and your avatar in the bottom left.
-- Shown after leaving a room (the toolbar's Habbo button), being kicked, banned, or while ringing a
-- doorbell; the toolbar's house goes home again.

BOBBA.hotelView = BOBBA.hotelView or {}
local HV = BOBBA.hotelView
local P = BOBBA.platform
local R = BOBBA.room
local V = BOBBA.view
local U = BOBBA.ui

HV.COLOR = Color(110, 173, 200) -- (#6eadc8, nitro-react's background.colour)

local function drawPicture(p, x, y, w, h)
	if not p or not p.material then return end
	surface.SetMaterial(p.material)
	surface.SetDrawColor(255, 255, 255, 255)
	local u, v = p.u or 1, p.v or 1
	surface.DrawTexturedRectUV(math.floor(x), math.floor(y), math.floor(w), math.floor(h), 0, 0, u, v)
end

local function paint(self, W, H)
	local s = U.scale()
	-- (above the toolbar, 55 high)
	local bottom = H - math.floor(55 * s)
	local l = HV.provider and HV.provider() or {}
	local c = l.color or HV.COLOR
	surface.SetDrawColor(c.r, c.g, c.b, 255)
	surface.DrawRect(0, 0, W, H)
	-- the sky: Habbo's gradient, as wide as the screen and as high as the view
	if l.background then drawPicture(l.background, 0, 0, W, bottom) end
	-- the hotel in the bottom left; its top repeated above it up to the top of the screen
	if l.left then
		local lw, lh = l.left.width * s, l.left.height * s
		if l.top then
			local tw, th = l.top.width * s, l.top.height * s
			local y = bottom - lh - th
			while y > -th do
				drawPicture(l.top, 0, y, tw, th)
				y = y - th
			end
		end
		drawPicture(l.left, 0, bottom - lh, lw, lh)
	end
	if l.right then
		local rw, rh = l.right.width * s, l.right.height * s
		drawPicture(l.right, W - rw, bottom - rh, rw, rh)
	end
	-- you (Nitro: the large avatar facing right, 114 from the left and 24 up)
	local me = BOBBA.hud and BOBBA.hud.lastMe
	if me and R.figureDrawer then
		HV.unit = HV.unit or { id = "hotelview" }
		HV.unit.figure, HV.unit.gender = me.figure, me.gender
		render.PushFilterMag(TEXFILTER.POINT)
		render.PushFilterMin(TEXFILTER.POINT)
		pcall(R.figureDrawer, HV.unit, { x = 0, y = 0, z = 0, sx = math.floor((114 + 45) * s), sy = bottom - math.floor(24 * s), k = s, dir = 2, posture = "std", now = SysTime(), talk = false })
		render.PopFilterMin()
		render.PopFilterMag()
	end
end

function HV.show()
	if not IsValid(HV.panel) then
		local p = vgui.Create("EditablePanel")
		p:SetZPos(-10)
		p.Paint = paint
		HV.panel = p
	end
	HV.panel:SetPos(0, 0)
	HV.panel:SetSize(ScrW(), ScrH())
	HV.panel:SetVisible(true)
	gui.EnableScreenClicker(true)
end

function HV.hide()
	if IsValid(HV.panel) then HV.panel:SetVisible(false) end
end

P.receive("room.hotelview", function()
	R.current = nil
	R.units, R.items = {}, {}
	R.selected, R.selectedUnit, R.placing = nil, nil, nil
	if BOBBA.roomWindows then BOBBA.roomWindows.menu = nil end
	if R.updateInfo then R.updateInfo() end
	V.hide()
	V.mode = "hotelview"
	HV.show()
	BOBBA.events.emit("hotelViewShown")
end)

BOBBA.events.on("roomShown", "bobba.hotelview", function() HV.hide() end)
hook.Add("OnScreenSizeChanged", "bobba.hotelview", function()
	if IsValid(HV.panel) then HV.panel:SetSize(ScrW(), ScrH()) end
end)
