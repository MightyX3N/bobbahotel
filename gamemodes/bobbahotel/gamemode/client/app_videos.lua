-- Videos (client): the room's TV (hotel/videos.lua) on the tablet, and while the tablet's away a
-- small player in the corner of the room. Plays in GMod's browser (YouTube's player); the desktop app
-- has no browser yet, so there it shows the queue and says so. "Watch here" plays a video for you
-- only, on the tablet (the room's TV is quiet meanwhile).

BOBBA.videos = BOBBA.videos or {}
local VID = BOBBA.videos
local DV = BOBBA.device
local U = BOBBA.ui
local P = BOBBA.platform
local R = BOBBA.room
local V = BOBBA.view
local C, G = DV.C, DV.G
local alpha = DV.alpha
local hex = DV.hex
local T = function(k, f, v) return U.text(k, f, v) end

VID.state = VID.state or nil
VID.volumeVar = CreateClientConVar("bobba_videos_volume", "60", true, false, "The room TV's volume (0-100)")
VID.showVar = CreateClientConVar("bobba_videos_show", "1", true, false, "The room's TV in the corner while the tablet's away (1) or not (0)")

-- can this game play videos (GMod's browser panel)?
function VID.canPlay()
	if VID.playable ~= nil then return VID.playable end
	VID.playable = (vgui.GetControlTable ~= nil and vgui.GetControlTable("DHTML") ~= nil) and true or false
	return VID.playable
end

P.receive("videos.state", function(_, data)
	VID.state = data
	VID.stateAt = SysTime()
end)
P.receive("videos.error", function(_, data)
	if BOBBA.social then BOBBA.social.notify({ app = "videos", title = T("bobba.phone.couldnt", "Couldn't do that"), text = (tostring(data.message or ""):gsub("^%l", string.upper)) }) end
end)
BOBBA.events.on("roomShown", "bobba.videos", function() VID.state = nil P.send("videos.get", {}) end)
BOBBA.events.on("hotelViewShown", "bobba.videos", function() VID.state = nil end)

-- where in the playing video we are (seconds)
local function offset()
	local st = VID.state
	local p = st and st.playing
	if not p then return 0 end
	return math.max(0, (st.now - (p.startedAt or st.now)) + (SysTime() - (VID.stateAt or SysTime())))
end

-- --- thumbnails (YouTube's pictures, kept in data/) ----------------------------------------------------
VID.thumbs = VID.thumbs or {}
function VID.thumb(video)
	if not video then return nil end
	local t = VID.thumbs[video]
	if t == nil then
		VID.thumbs[video] = false
		local path = "videothumbs/" .. video .. ".jpg"
		if P.dataExists(path) then VID.thumbs[video] = P.dataMaterial(path, "smooth")
		else
			P.httpGet("https://i.ytimg.com/vi/" .. video .. "/mqdefault.jpg", function(body)
				P.writeData(path, body)
				VID.thumbs[video] = P.dataMaterial(path, "smooth")
			end, function() end)
		end
		return nil
	end
	return t or nil
end

-- --- the player (one browser panel: in the tablet, or in the corner) ------------------------------------
local function html(video, start, volume)
	return ([[<!doctype html><html><head><style>html,body,#p{margin:0;width:100%%;height:100%%;background:#000;overflow:hidden}</style></head>
<body><div id="p"></div><script src="https://www.youtube.com/iframe_api"></script><script>
var player;
function onYouTubeIframeAPIReady(){player=new YT.Player('p',{width:'100%%',height:'100%%',videoId:'%s',
playerVars:{autoplay:1,start:%d,controls:0,rel:0,modestbranding:1,playsinline:1,disablekb:1,iv_load_policy:3},
events:{onReady:function(e){e.target.setVolume(%d);e.target.playVideo();var d=e.target.getVideoData();try{bobba.meta(d.title||'',e.target.getDuration()||0);}catch(x){}},
onStateChange:function(e){if(e.data===0){try{bobba.ended();}catch(x){}}}}});}
function setVol(v){if(player&&player.setVolume){player.setVolume(v);}}
</script></body></html>]]):format(video, math.floor(start), volume)
end

-- what should play now: { key, video, start, room = bool } or nil
local function wanted()
	if VID.personal then return { key = "me:" .. VID.personal.video, video = VID.personal.video, start = 0 } end
	local st = VID.state
	if not st or not st.on or not st.playing or V.mode ~= "room" then return nil end
	return { key = "tv:" .. st.playing.id, video = st.playing.video, start = offset(), id = st.playing.id, room = true }
end

-- where it is: the tablet's Videos app (DV.videoRect, in its points) or the corner
local function placeFor()
	local inTablet = DV.active() and DV.kind == "tablet" and DV.shown and (DV.open or 0) > 0.99 and DV.current() and DV.current().id == "videos"
		and DV.videoRect and DV.surface and not DV.locked and DV.shade < 0.02 and not DV.question
	if inTablet then
		local r, s = DV.videoRect, DV.surface.s or 1
		return DV.surface.panel, math.floor(r.x * s), math.floor(r.y * s), math.floor(r.w * s), math.floor(r.h * s)
	end
	if VID.personal then return nil end
	if not VID.showVar:GetBool() or (DV.active() and DV.covering()) or (BOBBA.loading and BOBBA.loading.active) then return nil end
	-- (the corner: the top right, under the room's tools)
	local s = U.scale()
	local w, h = math.floor(320 * s), math.floor(180 * s)
	local m = math.floor(math.min(ScrW(), ScrH()) * 0.025)
	return nil, ScrW() - w - m * 2, m + math.floor(80 * s), w, h, true
end

local function makePanel()
	local p = vgui.Create("DHTML")
	p:SetAllowLua(false)
	p:AddFunction("bobba", "meta", function(title, duration)
		local cur = VID.playingKey and VID.cur
		if cur and cur.room then P.send("videos.meta", { id = cur.id, title = tostring(title or ""), duration = tonumber(duration) }) end
	end)
	p:AddFunction("bobba", "ended", function()
		local cur = VID.cur
		if cur and cur.room then P.send("videos.ended", { id = cur.id }) end
		if cur and not cur.room then VID.personal = nil end
	end)
	return p
end

-- (the corner's frame: a dark rounded box behind the video, its title, close)
local function cornerFrame()
	if IsValid(VID.frame) then return VID.frame end
	local f = vgui.Create("EditablePanel")
	f:SetZPos(15)
	f.Paint = function(self, w, h)
		draw.RoundedBox(math.floor(14 * U.scale()), 0, 0, w, h, Color(5, 8, 15, 240))
		local st = VID.state
		local title = st and st.playing and (st.playing.title or "YouTube") or ""
		draw.SimpleText(title, DV.font(12, 700, U.scale()), math.floor(12 * U.scale()), h - math.floor(14 * U.scale()), Color(244, 246, 251), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("×", DV.font(16, 800, U.scale()), w - math.floor(14 * U.scale()), h - math.floor(15 * U.scale()), Color(201, 210, 229), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	f.OnMousePressed = function(self, code)
		local mx = self:CursorPos()
		if mx > self:GetWide() - math.floor(30 * U.scale()) then RunConsoleCommand("bobba_videos_show", "0")
		elseif DV.active() then DV.openApp("videos") end
	end
	VID.frame = f
	return f
end

hook.Add("Think", "bobba.videos.player", function()
	if not VID.canPlay() then return end
	local want = wanted()
	local parent, x, y, w, h, corner = placeFor()
	if not want or not x then
		if IsValid(VID.panel) then VID.panel:Remove() end
		if IsValid(VID.frame) then VID.frame:SetVisible(false) end
		VID.panel, VID.playingKey, VID.cur = nil, nil, nil
		return
	end
	if not IsValid(VID.panel) then VID.panel = makePanel() VID.playingKey = nil end
	local p = VID.panel
	-- (where it is: the tablet, or a frame in the corner)
	if corner then
		local f = cornerFrame()
		f:SetVisible(true)
		local pad = math.floor(6 * U.scale())
		local bar = math.floor(28 * U.scale())
		f:SetPos(x - pad, y - pad)
		f:SetSize(w + pad * 2, h + pad * 2 + bar)
		if p:GetParent() ~= f then p:SetParent(f) end
		p:SetPos(pad, pad)
	else
		if IsValid(VID.frame) then VID.frame:SetVisible(false) end
		if p:GetParent() ~= parent then p:SetParent(parent) end
		p:SetPos(x, y)
	end
	if p:GetWide() ~= w or p:GetTall() ~= h then p:SetSize(w, h) end
	if VID.playingKey ~= want.key then
		VID.playingKey = want.key
		VID.cur = want
		p:SetHTML(html(want.video, want.start, VID.volumeVar:GetInt()))
	end
	-- (the volume, as it's changed)
	local vol = VID.volumeVar:GetInt()
	if VID.lastVol ~= vol then VID.lastVol = vol p:RunJavascript("setVol(" .. vol .. ")") end
end)

-- --- the app ----------------------------------------------------------------------------------------
local function videosView(ctx)
	local d, W, H = ctx.d, ctx.w, ctx.h
	local st = VID.state
	if not ctx.state.asked then ctx.state.asked = true P.send("videos.get", {}) end
	d:rect(0, 0, W, H, hex("0B1220"))
	local top = ctx.top + 6
	local rw = 330
	local mx, mw = 28, W - 28 - rw - 24 - 28
	-- the header
	d:round(11, mx, top, 34, 34, C.red)
	d:glyph("M8 5l11 7-11 7z", mx + 7, top + 7, 20, C.paper, 2, true)
	d:text(T("bobba.phone.app.videos", "Videos"), 20, mx + 46, top + 17, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 800)
	local where
	if V.mode ~= "room" then where = T("bobba.videos.noroom", "Go into a room to watch its TV")
	elseif st and not st.on then where = T("bobba.videos.off", "The room's TV is off")
	else where = T("bobba.videos.on", "On %room%'s TV · %n% watching", { room = R.current and R.current.name or "", n = st and st.watching or 1 }) end
	local ww = d:textWidth(where, 13, 700) + 40
	d:pill(mx + mw - ww, top + 3, ww, 28, C.navy2)
	d:circle(mx + mw - ww + 16, top + 17, 4, (st and st.on and st.playing) and C.green or C.slate)
	d:text(where, 13, mx + mw - ww + 28, top + 17, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 700)
	-- the player
	local py = top + 48
	local ph = math.min(400, mw * 9 / 16)
	local pw = ph * 16 / 9
	local px = mx + (mw - pw) / 2
	d:round(24, mx, py, mw, ph, C.navy2)
	DV.videoRect = { x = px, y = py, w = pw, h = ph }
	local playing = VID.personal or (st and st.on and st.playing)
	if not VID.canPlay() then
		DV.videoRect = nil
		for i, l in ipairs(d:wrap(T("bobba.videos.desktop", "Videos play in Garry's Mod. The desktop app can't play them yet, but you can add to the TV's queue here."), 15, mw - 120)) do
			d:text(l, 15, mx + mw / 2, py + ph / 2 - 20 + (i - 1) * 22, C.mist, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
		end
	elseif not playing then
		DV.videoRect = nil
		d:glyph("M8 5l11 7-11 7z", mx + mw / 2 - 30, py + ph / 2 - 50, 60, alpha(C.paper, 0.3), 2, true)
		d:text(T("bobba.videos.nothing", "Nothing on. Add a video on the right."), 15, mx + mw / 2, py + ph / 2 + 30, C.mist, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 600)
	end
	-- (its time: the bar under it)
	local p = st and st.playing
	if p and p.duration and not VID.personal then
		local t = math.min(p.duration, offset())
		d:pill(mx + 20, py + ph + 10, mw - 40, 6, alpha(C.paper, 0.25))
		d:pill(mx + 20, py + ph + 10, math.max(6, (mw - 40) * t / p.duration), 6, C.red)
	end
	local y = py + ph + 26
	if VID.personal then
		d:text(T("bobba.videos.yours", "Just for you"), 20, mx, y, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
		d:text(T("bobba.videos.yourssub", "The room's TV is quiet while this plays."), 14, mx, y + 30, C.mist)
		d.bgUnder = hex("0B1220")
		d:button(mx + mw - 200, y, 200, 44, T("bobba.videos.backtv", "Back to the TV"), "paper", function() VID.personal = nil end)
		d.bgUnder = nil
	elseif p then
		d:text(d:fit(p.title or T("bobba.videos.untitled", "A video"), 20, mw - (VID.canPlay() and 380 or 190), 800), 20, mx, y, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
		local bw = VID.canPlay() and 360 or 170
		d:text(d:fit(T("bobba.videos.addedby", "Added by %name% · %v% of %n% votes to skip", { name = p.by or "", v = p.votes or 0, n = p.need or 1 }), 14, mw - bw - 20), 14, mx, y + 30, C.mist)
		d.bgUnder = hex("0B1220")
		d:button(mx + mw - bw, y, 170, 44, p.voted and T("bobba.videos.voted", "You voted") or T("bobba.videos.skip", "Vote to skip"), "outlineLight", function() P.send("videos.skip", {}) end, p.voted)
		d.bgUnder = nil
		if VID.canPlay() then
			d:button(mx + mw - 180, y, 180, 44, VID.showVar:GetBool() and T("bobba.videos.hide", "Hide the TV") or T("bobba.videos.show", "Show the TV"), "paper", function()
				RunConsoleCommand("bobba_videos_show", VID.showVar:GetBool() and "0" or "1")
			end)
		end
	end
	-- up next
	y = y + 70
	d:text(T("bobba.videos.next", "Up next on the TV"), 15, mx, y, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	y = y + 28
	local queue = st and st.queue or {}
	if #queue == 0 then d:text(T("bobba.videos.empty", "Nothing waiting."), 13, mx, y + 6, C.slate) end
	local cw = (mw - 28) / 3
	for i, q in ipairs(queue) do
		if i > 6 then break end
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local qx, qy = mx + col * (cw + 14), y + row * 68
		if qy + 60 < H then
			d:round(12, qx, qy, 96, 54, C.navy3)
			local mat = VID.thumb(q.video)
			if mat then d:clip(qx, qy, 96, 54, function() d:material(mat, qx, qy, 96, 54) end) end
			d:text(d:fit(q.title or T("bobba.videos.untitled", "A video"), 13, cw - 110, 700), 13, qx + 106, qy + 12, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
			d:text(d:fit(q.by or "", 12, cw - 110), 12, qx + 106, qy + 32, C.mist)
		end
	end
	-- the right: add one
	local rx = W - rw - 24
	d:round(26, rx, ctx.top + 6, rw, H - ctx.top - 30, C.navy2)
	local ry = ctx.top + 24
	d:text(T("bobba.videos.add", "Add a video"), 17, rx + 18, ry, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
	ry = ry + 34
	local e = d:input("videourl", rx + 18, ry, rw - 36, 44, { placeholder = T("bobba.videos.paste", "Paste a YouTube link"), max = 200, bg = C.navy, fg = C.paper,
		onEnter = function(t) if (t or "") ~= "" then P.send("videos.add", { url = t }) end end })
	ry = ry + 56
	local half = (rw - 36 - 10) / 2
	d:button(rx + 18, ry, half, 44, T("bobba.videos.addtv", "Add to the TV"), "paper", function()
		local t = e:GetValue() or ""
		if t ~= "" then P.send("videos.add", { url = t }) e:SetText("") end
	end, V.mode ~= "room")
	d.bgUnder = C.navy2
	d:button(rx + 18 + half + 10, ry, half, 44, T("bobba.videos.watchhere", "Watch here"), "outlineLight", function()
		local t = e:GetValue() or ""
		local id = t:match("youtu%.be/([%w_%-]+)") or t:match("[?&]v=([%w_%-]+)") or t:match("shorts/([%w_%-]+)") or (t:match("^[%w_%-]+$") and #t == 11 and t)
		if id then VID.personal = { video = id } e:SetText("") end
	end, not VID.canPlay())
	d.bgUnder = nil
	ry = ry + 64
	-- the queue: yours to take off (or any, with rights)
	if #queue > 0 then
		d:text(T("bobba.videos.queue", "IN THE QUEUE"), 12, rx + 18, ry, C.slate, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 800)
		ry = ry + 22
		local me = LocalPlayer and IsValid(LocalPlayer()) and LocalPlayer():Nick()
		for i, q in ipairs(queue) do
			if ry > H - 200 then break end
			d:text(d:fit(i .. ". " .. (q.title or q.video), 13, rw - 90, 600), 13, rx + 18, ry + 10, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 600)
			if q.by == me or (st and st.canManage) then
				local hv = d:click(rx + rw - 50, ry - 2, 32, 24, function() P.send("videos.remove", { id = q.id }) end)
				d:text("×", 16, rx + rw - 34, ry + 10, hv and C.paper or C.mist, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 800)
			end
			ry = ry + 28
		end
		ry = ry + 10
	end
	-- the volume, and the owner's switch
	local by = H - 190
	d:text(T("bobba.videos.volume", "Volume"), 13, rx + 18, by, C.mist, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 700)
	DV.slider(d, rx + 18, by + 22, rw - 36, 14, VID.volumeVar:GetInt() / 100, function(v) RunConsoleCommand("bobba_videos_volume", tostring(math.floor(v * 100 + 0.5))) end, C.paper, C.navy3)
	if st and st.canManage and V.mode == "room" then
		d:button(rx + 18, by + 52, rw - 36, 40, st.on and T("bobba.videos.turnoff", "Turn the room's TV off") or T("bobba.videos.turnon", "Turn the room's TV on"), "light", function()
			P.send("videos.room", { on = not st.on })
		end)
	end
	for i, l in ipairs(d:wrap(T("bobba.videos.note", "The hotel and the room's owner choose what plays here."), 12, rw - 36)) do
		d:text(l, 12, rx + 18, H - 82 + (i - 1) * 16, C.slate)
	end
end

DV.app({ id = "videos", name = T("bobba.phone.app.videos", "Videos"), color = C.red, glyph = G.videos, order = 18, bg = hex("0B1220"),
	description = T("bobba.videos.desc", "Watch together on the room's TV"),
	tablet = videosView,
	onClose = function() DV.videoRect = nil end })
