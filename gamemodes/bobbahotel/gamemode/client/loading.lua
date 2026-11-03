-- The hotel's loading screen (client): after GMod's own loading screen, until the first room is
-- ready to show complete (its floor and walls, its furni and everyone in it), like Habbo's loading
-- screen before the hotel. Drawn the way nitro-react's LoadingView is: $primary, the percentage and
-- a large progress bar at the bottom. Addons say what to wait for:
--
--   BOBBA.loading.add(id, function() return done, fraction end)   -- fraction 0..1, optional
--   BOBBA.loading.active   true while it's shown
--
-- It never waits longer than BOBBA.loading.MAX_WAIT seconds (then the room shows as it is).

BOBBA.loading = BOBBA.loading or { checks = {}, order = {} }
local LD = BOBBA.loading
local R = BOBBA.room
local U = BOBBA.ui

LD.MAX_WAIT = 60
LD.started = LD.started or SysTime()
if LD.active == nil then LD.active = true end

function LD.add(id, fn)
	if not LD.checks[id] then LD.order[#LD.order + 1] = id end
	LD.checks[id] = fn
end

-- how far it is: 0..1 (the room counts as one step, each check as one; the room is only there when
-- the server has said what all its furni are)
function LD.progress()
	-- (or the hotel view: a new player picking a room, someone waiting at a doorbell)
	local roomThere = (R and R.current and not (R.itemsComing and next(R.itemsComing))) or (BOBBA.view and BOBBA.view.mode == "hotelview")
	local total, done = 1, roomThere and 1 or 0
	local allDone = done == 1
	for _, id in ipairs(LD.order) do
		local ok, isDone, fraction = pcall(LD.checks[id])
		total = total + 1
		if ok and isDone then
			done = done + 1
		else
			allDone = false
			if ok and fraction then done = done + math.Clamp(fraction, 0, 0.99) end
		end
	end
	return done / total, allDone
end

local shown = 0 -- (the bar glides, like Nitro's transition: all 1s)

local function paint(w, h)
	local s = U and U.scale() or 1
	local C = U and U.C or { primary = Color(30, 114, 149), white = Color(255, 255, 255) }
	surface.SetDrawColor(C.primary.r, C.primary.g, C.primary.b, 255)
	surface.DrawRect(0, 0, w, h)
	local target = LD.progress()
	shown = shown + (target - shown) * math.min(1, RealFrameTime() * 3)
	-- the bottom middle: half the width of Bootstrap's container (1320 / 1140 / 960 / 720 / 540)
	local cw = w / s
	local container = cw >= 1400 and 1320 or cw >= 1200 and 1140 or cw >= 992 and 960 or cw >= 768 and 720 or cw >= 576 and 540 or cw
	local bw = (container - 24) / 2
	local bx = (cw - bw) / 2
	local by = h / s - 24 - 30
	local function R2(x, y, ww, hh, r, c) draw.RoundedBox(math.floor(r * s), math.floor(x * s), math.floor(y * s), math.floor(ww * s), math.floor(hh * s), c) end
	-- .nitro-progress-bar.large: 30 high, a white border, 2 inside, the bar in two blues
	R2(bx, by, bw, 30, 4, C.white)
	R2(bx + 1, by + 1, bw - 2, 28, 3, C.primary)
	local iw = math.floor((bw - 6) * shown)
	if iw > 0 then
		R2(bx + 3, by + 3, iw, 12, 2, Color(45, 171, 194))
		R2(bx + 3, by + 15, iw, 12, 2, Color(43, 145, 167))
	end
	-- the percentage above it (fs-4, white, text-shadow 0 4px 4px rgba(0,0,0,.25))
	local font = U and U.font(21.6) or "DermaLarge"
	local text = string.format("%d%%", math.floor(target * 100))
	draw.SimpleText(text, font, math.floor(cw / 2 * s), math.floor((by - 8) * s) + math.floor(2 * s), Color(0, 0, 0, 64), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
	draw.SimpleText(text, font, math.floor(cw / 2 * s), math.floor((by - 8) * s), C.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
end
LD.paint = paint

-- a panel over everything while it loads (it also keeps clicks and typing from the room)
hook.Add("Think", "bobba.loading", function()
	if not LD.active then return end
	if not IsValid(LD.panel) then
		local p = vgui.Create("EditablePanel")
		p:SetPos(0, 0)
		p:SetSize(ScrW(), ScrH())
		p:MakePopup()
		p.Paint = function(self, w, h) paint(w, h) end
		LD.panel = p
	end
	-- (the game's window changed size)
	if LD.panel:GetWide() ~= ScrW() or LD.panel:GetTall() ~= ScrH() then LD.panel:SetSize(ScrW(), ScrH()) end
	local _, allDone = LD.progress()
	if allDone or SysTime() - LD.started > LD.MAX_WAIT then
		LD.active = false
		if IsValid(LD.panel) then LD.panel:Remove() end
		BOBBA.events.emit("loadingDone")
	end
end)
