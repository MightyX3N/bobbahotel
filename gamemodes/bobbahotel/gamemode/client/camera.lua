-- The camera (client), nitro-react's CameraWidgetCaptureView and CameraWidgetCheckoutView with
-- Habbo's own pictures of it: a viewfinder over the room, the shutter, a roll of up to five shots;
-- a shot can be bought as a photo (a furni to hang on a wall, which shows it) for the hotel's
-- price. The room info's camera (owners) is LayoutMiniCameraView: the room's 110 x 110 thumbnail.
-- Pictures are of the room alone (no windows over it), as Nitro's createTextureFromRoom makes them.
-- The server's side is hotel/photos.lua.
--
--   BOBBA.camera.drawPhoto(d, id, x, y, w, h)   a photo or thumbnail from the server (fetched once)

BOBBA.camera = BOBBA.camera or { roll = {}, photos = {} }
local CAM = BOBBA.camera
local U = BOBBA.ui
local P = BOBBA.platform
local R = BOBBA.room
local V = BOBBA.view
local HUD = BOBBA.hud
local T = function(key, fallback, vars) return U.text(key, fallback, vars) end

CAM.ROLL_LIMIT = 5
CAM.SIZE = 320
CAM.THUMB = 110
CAM.PIECE = 12000

local WHITE, BLACK = Color(255, 255, 255), Color(0, 0, 0)
local shotCount = 0

-- --- pictures from the server -------------------------------------------------------------------------
-- (pieces come in; the PNG is written to the data folder and drawn from there)
local incoming = {}
P.receive("photo.data", function(_, data)
	local id = tonumber(data.id) or 0
	local p = CAM.photos[id]
	if not p then return end
	if (tonumber(data.n) or 0) < 1 then p.state = "missing" return end
	local inc = incoming[id] or { got = {}, n = tonumber(data.n), count = 0 }
	incoming[id] = inc
	local i = tonumber(data.i) or 0
	if not inc.got[i] then inc.count = inc.count + 1 end
	inc.got[i] = data.data or ""
	if inc.count < inc.n then return end
	incoming[id] = nil
	local parts = {}
	for k = 1, inc.n do parts[k] = inc.got[k] or "" end
	local bytes = BOBBA.util.base64Decode(table.concat(parts))
	if not bytes then p.state = "missing" return end
	local path = "photocache/" .. id .. ".png"
	P.writeData(path, bytes)
	p.material = P.dataMaterial(path, "noclamp smooth")
	p.state = "ready"
end)

-- the material of photo id (asked for the first time it's wanted), or nil while it comes
function CAM.photo(id)
	id = tonumber(id) or 0
	if id <= 0 then return nil end
	local p = CAM.photos[id]
	if not p then
		p = { state = "loading" }
		CAM.photos[id] = p
		-- (fetched before: from the data folder)
		local path = "photocache/" .. id .. ".png"
		if P.dataExists(path) then
			p.material, p.state = P.dataMaterial(path, "noclamp smooth"), "ready"
		else
			P.send("photo.get", { id = id })
		end
	end
	return p.state == "ready" and p.material or nil
end

local function drawMaterial(d, mat, x, y, w, h)
	local s = d.s
	surface.SetMaterial(mat)
	surface.SetDrawColor(255, 255, 255, 255)
	local X, Y = math.floor(x * s + 0.5), math.floor(y * s + 0.5)
	surface.DrawTexturedRect(X, Y, math.floor((x + w) * s + 0.5) - X, math.floor((y + h) * s + 0.5) - Y)
end

-- a photo in a window (CSS px); false while it isn't here yet
function CAM.drawPhoto(d, id, x, y, w, h)
	local mat = CAM.photo(id)
	if not mat then return false end
	drawMaterial(d, mat, x, y, w, h)
	return true
end

-- --- taking pictures ---------------------------------------------------------------------------------------
-- The room under a square of the screen (screen pixels: its middle and size) as a PNG: cb(bytes)
local function shoot(cx, cy, size, cb)
	local x, y = math.floor(cx - size / 2), math.floor(cy - size / 2)
	P.renderPNG(x, y, size, size, function()
		V.capturing = true
		local ok, err = pcall(V.drawScene)
		V.capturing = false
		if not ok then error(err) end
	end, function(bytes)
		if bytes then
			if BOBBA.sounds and BOBBA.sounds.play then pcall(BOBBA.sounds.play, "camera_shutter") end
		end
		cb(bytes)
	end)
end

local function upload(purpose, bytes)
	local text = BOBBA.util.base64Encode(bytes)
	local n = math.max(1, math.ceil(#text / CAM.PIECE))
	local token = tostring(math.floor(SysTime() * 1000)) .. "_" .. math.random(1, 99999)
	for i = 1, n do
		P.send("camera.upload", { up = token, i = i, n = n, purpose = purpose, data = text:sub((i - 1) * CAM.PIECE + 1, i * CAM.PIECE) })
	end
end

-- a shot from the roll as a material (written to the data folder under a new name each time: a
-- material is kept by its name)
local function rollPicture(bytes)
	shotCount = shotCount + 1
	local path = "camera/shot_" .. os.time() .. "_" .. shotCount .. ".png"
	P.writeData(path, bytes)
	return { bytes = bytes, path = path, material = P.dataMaterial(path, "noclamp smooth") }
end

-- --- the camera window (CameraWidgetCaptureView: 340 x 462, the roll under it) --------------------------
local VIEW = { x = 10, y = 37, w = 320, h = 320 }
local function drawCapture(w, d)
	if V.mode ~= "room" then w:close() return end
	local s = d.s
	local roll = CAM.roll
	local H = 462 + (#roll > 0 and (56 + 16) or 0)
	w:setHeight(H)
	-- the roll: 330 wide, #bab8b4, under the camera
	if #roll > 0 then
		d:round(10, 5, 462 - 10, 330, 56 + 16 + 10, Color(186, 184, 180))
		local rx = 170 - (#roll * 56 + (#roll - 1) * 8) / 2
		for i, pic in ipairs(roll) do
			local px = rx + (i - 1) * 64
			d:click(px, 462 + 8, 56, 56, function() CAM.selected = (CAM.selected == i) and nil or i end)
			drawMaterial(d, pic.material, px, 462 + 8, 56, 56)
			if CAM.selected == i then
				d:rect(px - 2, 462 + 6, 60, 2, WHITE) d:rect(px - 2, 462 + 64, 60, 2, WHITE)
				d:rect(px - 2, 462 + 6, 2, 60, WHITE) d:rect(px + 56, 462 + 6, 2, 60, WHITE)
			end
		end
	end
	-- the camera (Habbo's picture; its screen is see-through, the room shows there)
	local pic = CAM.selected and roll[CAM.selected]
	if pic then drawMaterial(d, pic.material, VIEW.x, VIEW.y, VIEW.w, VIEW.h) end
	if not d:icon("camera_cam_bg", 0, 0) then
		d:round(10, 0, 0, 340, VIEW.y, Color(45, 45, 45))
		d:round(10, 0, VIEW.y + VIEW.h, 340, 462 - VIEW.y - VIEW.h, Color(45, 45, 45), false, false, true, true)
		d:rect(0, VIEW.y, VIEW.x, VIEW.h, Color(45, 45, 45))
		d:rect(VIEW.x + VIEW.w, VIEW.y, 340 - VIEW.x - VIEW.w, VIEW.h, Color(45, 45, 45))
	end
	if not pic then
		d:icon("camera_viewfinder", VIEW.x + 1, VIEW.y + 1)
	else
		-- the shot's actions: edit (buy), delete
		d:rect(VIEW.x, VIEW.y + VIEW.h - 46, VIEW.w, 46, Color(0, 0, 0, 128))
		local et, dt = T("camera.editor.button.text", "Edit"), T("camera.delete.button.text", "Delete")
		local ew, dw = d:textWidth(et, 12.6) + 24, d:textWidth(dt, 12.6) + 24
		local bx = VIEW.x + (VIEW.w - ew - 16 - dw) / 2
		local by = VIEW.y + VIEW.h - 46 + 9
		d:btn(bx, by, ew, 28, U.C.success, function() CAM.openCheckout(CAM.selected) end)
		d:text(et, 12.6, bx + ew / 2, by + 14, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		d:btn(bx + ew + 16, by, dw, 28, U.C.danger, function()
			table.remove(CAM.roll, CAM.selected)
			CAM.selected = nil
		end)
		d:text(dt, 12.6, bx + ew + 16 + dw / 2, by + 14, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	-- the close button (top right)
	d:click(340 - 10 - 22, 8, 22, 22, function() w:close() end)
	if not d:icon("camera_cam_close_x", 340 - 10 - 19 - 2, 8) then d:fa("times", 340 - 10 - 18, 10, 14, WHITE) end
	-- the shutter (94 x 94, 362 down): a shot (or back to the viewfinder)
	local bx, by = 170 - 47, 362
	local down = CAM.pressed and input.IsMouseDown(MOUSE_LEFT)
	if not input.IsMouseDown(MOUSE_LEFT) then CAM.pressed = false end
	local hover = d:click(bx + 6, by + 6, 82, 82, function()
		CAM.pressed = true
		if CAM.selected then CAM.selected = nil return end
		local ox, oy = w.panel:LocalToScreen(0, 0)
		local cx, cy = ox + (VIEW.x + VIEW.w / 2) * s, oy + (VIEW.y + VIEW.h / 2) * s
		shoot(cx, cy, CAM.SIZE, function(bytes)
			if not bytes then U.notify(T("camera.error.title", "Camera"), T("bobba.camera.failed", "The picture couldn't be taken."), 4) return end
			if #CAM.roll >= CAM.ROLL_LIMIT then
				U.alert(T("camera.full.header", "Camera roll full"), U.plain(T("camera.full.body", "Your camera roll is full: the oldest picture makes room.")))
				table.remove(CAM.roll, 1)
			end
			CAM.roll[#CAM.roll + 1] = rollPicture(bytes)
		end)
	end)
	local img = down and "camera_camera_btn_down" or (hover and "camera_cam_btn_hi" or "camera_camera_btn")
	if not d:icon(img, bx, by) then
		d:circle(bx + 47, by + 47, 40, down and Color(180, 30, 30) or Color(230, 50, 50))
	end
end

function CAM.open()
	if V.mode ~= "room" then return end
	U.toggle("camera", function()
		local w = U.window("camera", 340, 462, drawCapture)
		-- (the whole camera moves it: a window's header is its top 34)
		w.selectedOnOpen = nil
	end)
end
HUD.actions.camera = CAM.open

-- --- buying (CameraWidgetCheckoutView) ----------------------------------------------------------------------
local function drawCheckout(w, d)
	local pic = CAM.roll[w.index or 0]
	if not pic then w:close() return end
	local W = 400
	d:slimCard(T("camera.confirm_phase.title", "Photo"))
	local x, y = (W - 320) / 2, 31 + 9
	drawMaterial(d, pic.material, x, y, 320, 320)
	y = y + 320 + 10
	local price = CAM.price or { credits = 2, duckets = 0 }
	-- the price and the buy button
	local lines = d:wrap(U.plain(T("camera.purchase.header", "Buy this photo to hang it on a wall.")), 14.4, W - 18)
	for _, l in ipairs(lines) do d:text(l, 14.4, 9, y, BLACK) y = y + 21.6 end
	local pt = U.plain(T("catalog.purchase.price.credits", "%credits% credits", { credits = tostring(price.credits or 0) }))
	if (price.duckets or 0) > 0 then pt = pt .. " + " .. U.plain(T("catalog.purchase.price.activitypoints", "%activitypoints% duckets", { activitypoints = tostring(price.duckets) })) end
	d:text(pt, 14.4, 9, y + 14, BLACK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, true)
	local bt = w.bought and T("camera.purchase.successful.confirmation", "Bought!") or T("buy", "Buy")
	local bw = d:textWidth(bt, 12.6) + 30
	d:btn(W - 9 - bw, y, bw, 28, U.C.success, function()
		if w.bought or w.buying then return end
		w.buying = true
		CAM.checkout = w
		upload("photo", pic.bytes)
	end, w.bought or w.buying)
	d:text(bt, 12.6, W - 9 - bw / 2, y + 14, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	y = y + 28 + 9
	w:setHeight(y)
end

function CAM.openCheckout(index)
	local w = U.window("camera-checkout", 400, 480, drawCheckout)
	w.index = index
end

P.receive("camera.purchased", function()
	local w = CAM.checkout
	if w and U.windows["camera-checkout"] == w then w.buying, w.bought = false, true end
	U.notify(T("camera.purchase.successful.confirmation", "Photo bought"), T("bobba.camera.inventory", "It's in your inventory: hang it on a wall."), 5)
end)
P.receive("camera.error", function(_, data)
	local w = CAM.checkout
	if w then w.buying = false end
	U.alert(T("camera.error.title", "Camera"), tostring(data.message or ""))
end)

-- --- the room's thumbnail (LayoutMiniCameraView: 132 x 192, a 110 x 110 frame) ------------------------------
local function drawMini(w, d)
	if V.mode ~= "room" then w:close() return end
	local W, H = 132, 192
	-- (Habbo's dark camera, drawn: a frame round the see-through window)
	local body = Color(46, 46, 46)
	local fx, fy = 11, 30
	d:round(8, 0, 0, W, fy, body, true, true, false, false)
	d:rect(0, fy, fx, CAM.THUMB, body)
	d:rect(fx + CAM.THUMB, fy, W - fx - CAM.THUMB, CAM.THUMB, body)
	d:round(8, 0, fy + CAM.THUMB, W, H - fy - CAM.THUMB, body, false, false, true, true)
	d:rect(4, 4, W - 8, 1, Color(255, 255, 255, 40))
	d:rect(fx - 1, fy - 1, CAM.THUMB + 2, 1, BLACK) d:rect(fx - 1, fy + CAM.THUMB, CAM.THUMB + 2, 1, BLACK)
	d:rect(fx - 1, fy, 1, CAM.THUMB, BLACK) d:rect(fx + CAM.THUMB, fy, 1, CAM.THUMB, BLACK)
	local by = H - 8 - 26
	local bw = (W - 16 - 6) / 2
	d:btn(8, by, bw, 26, U.C.danger, function() w:close() end)
	d:text(T("cancel", "Cancel"), 11, 8 + bw / 2, by + 13, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	d:btn(8 + bw + 6, by, bw, 26, U.C.success, function()
		local s = d.s
		local ox, oy = w.panel:LocalToScreen(0, 0)
		shoot(ox + (fx + CAM.THUMB / 2) * s, oy + (fy + CAM.THUMB / 2) * s, CAM.THUMB, function(bytes)
			if bytes then upload("thumbnail", bytes) end
		end)
		w:close()
	end)
	d:text(T("navigator.thumbeditor.save", "Save"), 11, 8 + bw + 6 + bw / 2, by + 13, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function CAM.openThumbnail()
	if V.mode ~= "room" then return end
	U.toggle("room-thumbnail-camera", function() U.window("room-thumbnail-camera", 132, 192, drawMini) end)
end

P.receive("camera.thumbnail", function(_, data)
	if R.current and R.current.access and R.current.id == tonumber(data.room) then R.current.access.thumbnail = tonumber(data.id) end
	U.notify(T("navigator.thumbeditor.title", "Room thumbnail"), T("bobba.camera.thumbnail", "Your room's picture is saved."), 4)
end)

-- the camera's price, from the hotel (sent with the purse)
P.receive("camera.price", function(_, data) CAM.price = data end)

-- leaving the room: its camera windows close
BOBBA.events.on("roomShown", "bobba.camera", function(data)
	if U.windows["room-thumbnail-camera"] then U.windows["room-thumbnail-camera"]:close() end
end)

-- --- photos on walls: the photo furni shows its photo, a little picture leaning with the wall ------------
-- (its corners on screen: the wall's slope is half a pixel down per pixel across, down to the right on
-- a right-hand wall, down to the left on a left-hand one)
function CAM.photoSprite(it, info)
	local id = tonumber(it.data or it.photo or 0)
	local k = info.k or 1
	local W, H = 30 * k, 30 * k
	local dir = it.dir or 4
	local slope = (dir == 2) and -0.5 or 0.5
	local cx, cy = info.sx, info.sy - 24 * k
	local function corner(dx, dy) return { x = cx + dx, y = cy + dy + dx * slope } end
	local frame = { corner(-W / 2 - 3 * k, -H / 2 - 3 * k), corner(W / 2 + 3 * k, -H / 2 - 3 * k), corner(W / 2 + 3 * k, H / 2 + 6 * k), corner(-W / 2 - 3 * k, H / 2 + 6 * k) }
	local photo = { corner(-W / 2, -H / 2), corner(W / 2, -H / 2), corner(W / 2, H / 2), corner(-W / 2, H / 2) }
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(frame) do x0, y0, x1, y1 = math.min(x0, p.x), math.min(y0, p.y), math.max(x1, p.x), math.max(y1, p.y) end
	return { {
		depth = 0, x = x0, y = y0, w = x1 - x0, h = y1 - y0, mouse = true,
		draw = function()
			local a = math.floor(255 * (info.alpha or 1))
			draw.NoTexture()
			surface.SetDrawColor(245, 245, 240, a)
			surface.DrawPoly(V.clockwise(frame))
			local mat = CAM.photo(id)
			if mat then
				surface.SetMaterial(mat)
				surface.SetDrawColor(255, 255, 255, a)
				local uv = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }
				local pts = {}
				for i, p in ipairs(photo) do pts[i] = { x = p.x, y = p.y, u = uv[i][1], v = uv[i][2] } end
				surface.DrawPoly(pts)
			else
				surface.SetDrawColor(200, 200, 200, a)
				surface.DrawPoly(V.clockwise(photo))
			end
		end,
	} }
end
