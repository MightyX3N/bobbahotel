-- Habbo's room content: the floors and wallpapers (and the views out of the windows), from
-- HabboRoomContent.swf in Habbo's desktop client, and how a floor or wall is painted with them:
-- Nitro's plane rasterizers (FloorRasterizer, WallRasterizer, PlaneRasterizer, Plane, FloorPlane,
-- WallPlane, PlaneVisualization, PlaneVisualizationLayer, PlaneMaterial, PlaneMaterialCellMatrix,
-- PlaneMaterialCellColumn, PlaneMaterialCell, PlaneTexture; github.com/billsonnn/nitro-renderer,
-- GPL-3), followed line by line. Nitro paints into textures with PixiJS; here the same steps give
-- the list of pictures that make up the plane's texture (which part of which picture goes where),
-- so the game draws them straight onto the plane.
--
--   H.roomContent(function(rc, err) ... end)
--   H.paintPlane(rc, "floor" | "wall", id, plane)
--     plane: the view's plane (textureWidth, textureHeight, textureX, textureY, normal, texture)
--     -> { width, height, layers = { { color = 0xRRGGBB, fill = true } or
--                                    { color = 0xRRGGBB, quads = { { image, x, y, w, h, u0, v0, u1, v1 }, ... } } } }
--     (x, y, w, h: where in the plane's texture; u0..v1: which pixels of the picture, reversed when
--     mirrored). Layers are painted in order, each tinted with its colour.
--   H.roomIds(rc, "floor" | "wall")  -> the ids Habbo has, sorted

local H = BOBBA.habbo
local P = BOBBA.platform

H.ROOM_CONTENT = "room/HabboRoomContent"
H.ROOM_CONTENT_FILE = "local_include/HabboRoomContent.swf"

local function rawPath() return H.cachePath("raw/" .. H.ROOM_CONTENT, ".dat") end

-- the SWF out of Habbo's desktop client (a ZIP, opened) into the cache: true or nil, why
function H.saveRoomContentFromZip(zip)
	local swf, why2 = zip.read(H.ROOM_CONTENT_FILE, H.inflateRaw)
	if not swf then return nil, why2 end
	P.writeData(rawPath(), swf)
	return true
end

local function fetchRoomContent(cb)
	if P.dataExists(rawPath()) then cb(true) return end
	H.remembered("clienturls", H.CLIENT_URLS, function(json, why)
		if not json then cb(nil, "couldn't reach Habbo: " .. tostring(why)) return end
		local url = json:match('"flash%-windows"%s*:%s*"([^"]+)"')
		if not url then cb(nil, "Habbo didn't say where its desktop client is") return end
		H.httpGet(url:gsub("\\/", "/"), function(zipBytes)
			local zip, why2 = H.zip.open(zipBytes)
			if not zip then cb(nil, why2) return end
			cb(H.saveRoomContentFromZip(zip))
		end, function(e) cb(nil, e) end)
	end)
end

-- --- reading the XML (the shapes PlaneRasterizer reads) ---------------------------------------------
local function num(v, default)
	v = tonumber(v)
	if v == nil then return default end
	return v
end

local function color(v)
	if not v then return nil end
	local hex = v:match("^0[xX](%x+)$") or v:match("^#(%x+)$")
	if hex then return tonumber(hex, 16) end
	return tonumber(v)
end

local function kids(node, name)
	local out = {}
	for _, c in ipairs(node and node.children or {}) do
		if c.name == name then out[#out + 1] = c end
	end
	return out
end

local function kid(node, name) return kids(node, name)[1] end

local REPEAT_MATRIX = { borders = 2, center = 3, first = 4, last = 5, random = 6 }
local REPEAT_COLUMN = { borders = 2, center = 3, first = 4, last = 5, none = 0 }
local ALIGN_TOP, ALIGN_BOTTOM = 1, 2

local function normals(a)
	return num(a.normalMinX, -1), num(a.normalMaxX, 1), num(a.normalMinY, -1), num(a.normalMaxY, 1)
end

-- one section (wallData, floorData): its planes, materials and textures
local function section(node, planeName, assets, images)
	local s = { planes = {}, materials = {}, textures = {} }
	-- PlaneRasterizer.parseTextures
	for _, t in ipairs(kids(kid(node, "textures"), "texture")) do
		local id = t.attrs.id
		if id and not s.textures[id] then
			local bitmaps = {}
			for _, b in ipairs(kids(t, "bitmap")) do
				local name = b.attrs.assetName
				local asset = name and assets[name]
				local img = asset and images[asset.source or name]
				if img then
					local nx0, nx1, ny0, ny1 = normals(b.attrs)
					bitmaps[#bitmaps + 1] = { image = img, flipH = asset.flipH, normalMinX = nx0, normalMaxX = nx1, normalMinY = ny0, normalMaxY = ny1 }
				end
			end
			s.textures[id] = { bitmaps = bitmaps }
		end
	end
	-- PlaneRasterizer.parsePlaneMaterials
	for _, m in ipairs(kids(kid(node, "materials"), "material")) do
		local matrices = {}
		for _, mx in ipairs(kids(m, "materialCellMatrix")) do
			local columns = kids(mx, "materialCellColumn")
			if #columns > 0 then
				local nx0, nx1, ny0, ny1 = normals(mx.attrs)
				local matrix = {
					repeatMode = REPEAT_MATRIX[mx.attrs.repeatMode] or 1,
					align = (mx.attrs.align == "bottom") and ALIGN_BOTTOM or ALIGN_TOP,
					normalMinX = nx0, normalMaxX = nx1, normalMinY = ny0, normalMaxY = ny1,
					columns = {},
				}
				for i, c in ipairs(columns) do
					local cells = {}
					for _, cell in ipairs(kids(c, "materialCell")) do
						cells[#cells + 1] = { texture = s.textures[cell.attrs.textureId] }
					end
					matrix.columns[i] = {
						width = math.max(1, num(c.attrs.width, 1)),
						repeatMode = REPEAT_COLUMN[c.attrs.repeatMode] or 1,
						cells = cells,
					}
				end
				matrices[#matrices + 1] = matrix
			end
		end
		s.materials[m.attrs.id] = { matrices = matrices }
	end
	-- FloorRasterizer.parseFloors / WallRasterizer.parseWalls, PlaneRasterizer.parseVisualizations
	for _, p in ipairs(kids(kid(node, planeName .. "s"), planeName)) do
		local id = p.attrs.id
		if id and not s.planes[id] then
			local plane = { sizes = {}, visualizations = {} }
			for _, v in ipairs(kids(p, "visualization")) do
				local size = num(v.attrs.size, 64)
				if not plane.visualizations[size] then
					local layers = {}
					for i, l in ipairs(kids(v, "visualizationLayer")) do
						local c = color(l.attrs.color)
						local o = num(l.attrs.offset, 0)
						layers[i] = {
							material = l.attrs.materialId and s.materials[l.attrs.materialId] or nil,
							color = (c and c ~= 0) and c or 0xFFFFFF,
							offset = (o ~= 0) and o or 0,
							align = (l.attrs.align == "bottom") and ALIGN_BOTTOM or ALIGN_TOP,
						}
					end
					plane.visualizations[size] = { layers = layers }
					plane.sizes[#plane.sizes + 1] = size
				end
			end
			-- (Nitro sorts the sizes as text; 32 and 64 come out the same)
			table.sort(plane.sizes, function(a, b) return tostring(a) < tostring(b) end)
			s.planes[id] = plane
		end
	end
	return s
end

local roomContent, waiting
function H.roomContent(cb)
	if roomContent then cb(roomContent) return end
	if waiting then waiting[#waiting + 1] = cb return end
	waiting = { cb }
	local function done(rc, err)
		local list = waiting
		waiting = nil
		roomContent = rc
		for _, w in ipairs(list) do w(rc, err) end
	end
	fetchRoomContent(function(ok, err)
		if not ok then done(nil, "Habbo's room content: " .. tostring(err)) return end
		H.library(H.ROOM_CONTENT, "file://" .. rawPath(), function(lib, err2)
			if not lib then done(nil, err2) return end
			H.work(function()
				local vis = lib.xml["HabboRoomContent_room_visualization"]
				local assetsXml = lib.xml["HabboRoomContent_room_assets"]
				if not vis or not assetsXml then done(nil, "Habbo's room content has no room visualization") return end
				-- the pictures by their asset names (the SWF names them HabboRoomContent_<name>)
				local images = setmetatable({}, { __index = function(_, k) return lib.images["HabboRoomContent_" .. k] end })
				local assets = {}
				for _, a in ipairs(H.xml.all(H.xml.parse(assetsXml, H.yield), "asset")) do
					local n = a.attrs.name
					if n then assets[n] = { source = a.attrs.source, flipH = a.attrs.flipH == "1" } end
				end
				local root = H.xml.find(H.xml.parse(vis, H.yield), "visualizationData")
				if not root then done(nil, "Habbo's room visualization couldn't be read") return end
				local rc = {
					floor = section(kid(root, "floorData"), "floor", assets, images),
					wall = section(kid(root, "wallData"), "wall", assets, images),
				}
				done(rc)
			end)
		end)
	end)
end

function H.roomIds(rc, kind)
	local out = {}
	for id in pairs(rc[kind].planes) do
		if id ~= "default" then out[#out + 1] = id end
	end
	table.sort(out, function(a, b)
		local na, nb = tonumber(a), tonumber(b)
		if na and nb then return na < nb end
		return a < b
	end)
	return out
end

-- --- painting a plane --------------------------------------------------------------------------------
-- Plane.getSizeIndex / getPlaneVisualization
local function visualizationFor(plane, size)
	local sizes = plane.sizes
	local index = 1
	for i = 2, #sizes do
		if sizes[i] > size then
			if (sizes[i] - size) < (size - sizes[i - 1]) then index = i end
			break
		end
		index = i
	end
	return sizes[index] and plane.visualizations[sizes[index]]
end

local function inRange(n, o)
	return n[1] >= o.normalMinX and n[1] <= o.normalMaxX and n[2] >= o.normalMinY and n[2] <= o.normalMaxY
end

-- PlaneTexture.getBitmap
local function bitmapFor(texture, normal)
	if not texture then return nil end
	for _, b in ipairs(texture.bitmaps) do
		if inRange(normal, b) then return b end
	end
	return nil
end

-- One axis of a cell's picture (PlaneMaterialCell.render: a TilingSprite the picture's size, its
-- pattern moved by the texture offset; with an offset PixiJS mirrors it, scale -1 around the far
-- edge with the pattern starting there): the runs of plane pixels [p0, p1) and the picture's pixel
-- edges they show (t0 at p0, t1 at p1; t0 > t1 when mirrored).
local function axisRuns(from, to, size, offset)
	local runs = {}
	if size <= 0 or to <= from then return runs end
	local mirrored = offset ~= 0
	local shift = 0
	if mirrored then
		while offset < 0 do offset = offset + size end
		shift = offset % size
	end
	local p = from
	while p < to do
		local local0 = p - from
		if mirrored then
			-- picture pixel for plane pixel X: (-1 - X - shift) mod size, going down
			local t = (-1 - local0 - shift) % size
			local n = math.min(t + 1, to - p)
			runs[#runs + 1] = { p, p + n, t + 1, t + 1 - n }
			p = p + n
		else
			local t = local0 % size
			local n = math.min(size - t, to - p)
			runs[#runs + 1] = { p, p + n, t, t + n }
			p = p + n
		end
	end
	return runs
end

-- PlaneMaterialCell.render, written into a column at (x0, y0), cut to the column's rectangle
local function paintCell(out, bitmap, x0, y0, clipX1, clipY1, offsetX, offsetY)
	local img = bitmap.image
	local w, h = img.width, img.height
	local xs = axisRuns(x0, math.min(x0 + w, clipX1), w, offsetX)
	local ys = axisRuns(y0, math.min(y0 + h, clipY1), h, offsetY)
	for _, rx in ipairs(xs) do
		for _, ry in ipairs(ys) do
			local u0, u1 = rx[3], rx[4]
			-- a picture the room content mirrors itself (Rasterizer.getFlipHBitmapData)
			if bitmap.flipH then u0, u1 = w - u0, w - u1 end
			out[#out + 1] = { image = img, x = rx[1], y = ry[1], w = rx[2] - rx[1], h = ry[2] - ry[1], u0 = u0, v0 = ry[3], u1 = u1, v1 = ry[4] }
		end
	end
end

-- PlaneMaterialCellColumn.render (repeat all, and none): the cells top down, again and again
local function paintColumn(out, column, x, columnY, height, normal, offsetX, offsetY)
	local cells = column.cells
	if #cells == 0 then return 0 end
	if column.repeatMode == 0 then
		local total = 0
		for _, c in ipairs(cells) do
			local b = bitmapFor(c.texture, normal)
			if b then total = total + b.image.height end
		end
		height = total
	end
	local index = 0
	local function round()
		for _, c in ipairs(cells) do
			local b = bitmapFor(c.texture, normal)
			if b then
				paintCell(out, b, x, columnY + index, x + column.width, columnY + height, offsetX, offsetY)
				index = index + b.image.height
				if index >= height then return true end
			end
		end
		return false
	end
	if column.repeatMode == 0 then
		round()
	else
		while index < height do
			local before = index
			if round() or index == before then break end
		end
	end
	return height
end

-- PlaneMaterialCellMatrix.render (repeat all): the columns left to right, again and again
-- whole: the layer has a colour, so PlaneVisualizationLayer tints the matrix's whole texture and
-- puts it at the top (its offset and align only count for white layers, copyCachedBitmapOnCanvas)
local function paintMatrix(out, matrix, width, height, normal, offsetX, offsetY, layerOffset, layerTop, whole)
	if width < 1 then width = 1 end
	if height < 1 then height = 1 end
	local maxHeight = 0
	local x = 0
	local columns = matrix.columns
	if #columns == 0 then return end
	-- each column is a picture of its own (columnWidth x height), cut to the matrix's width
	local placed = {}
	while x < width do
		local before = x
		for _, column in ipairs(columns) do
			local colH = (column.repeatMode == 0) and nil or height
			placed[#placed + 1] = { column = column, x = x, height = colH }
			x = x + column.width
			if x >= width then break end
		end
		if x == before then break end
	end
	for _, p in ipairs(placed) do
		local h = p.height
		if not h then
			h = 0
			for _, c in ipairs(p.column.cells) do
				local b = bitmapFor(c.texture, normal)
				if b then h = h + b.image.height end
			end
		end
		if h > maxHeight then maxHeight = h end
		p.height = h
	end
	-- matrix align: bottom-aligned columns sit at the bottom of the matrix's own texture
	local tmp = {}
	for _, p in ipairs(placed) do
		local y = 0
		if matrix.align == ALIGN_BOTTOM then y = height - p.height end
		local q = {}
		paintColumn(q, p.column, p.x, y, p.height, normal, offsetX, offsetY)
		for _, quad in ipairs(q) do
			-- cut to the matrix's texture (width x height)
			if quad.x < width and quad.y < height and quad.y + quad.h > 0 then tmp[#tmp + 1] = quad end
		end
	end
	-- copyCachedBitmapOnCanvas: the used part (maxHeight tall) onto the plane, at the layer's offset
	local srcY = (matrix.align == ALIGN_BOTTOM) and (height - maxHeight) or 0
	local destY = layerOffset
	if not layerTop then destY = (height - maxHeight) - layerOffset end
	if whole then srcY, destY, maxHeight = 0, 0, height end
	for _, quad in ipairs(tmp) do
		local y0, y1 = math.max(quad.y, srcY), math.min(quad.y + quad.h, srcY + maxHeight)
		local x0, x1 = quad.x, math.min(quad.x + quad.w, width)
		if y1 > y0 and x1 > x0 then
			local fu = (quad.u1 - quad.u0) / quad.w
			local fv = (quad.v1 - quad.v0) / quad.h
			local ny0, ny1 = y0 - srcY + destY, y1 - srcY + destY
			-- and to the plane's texture
			local cy0, cy1 = math.max(ny0, 0), math.min(ny1, height)
			if cy1 > cy0 then
				y0 = y0 + (cy0 - ny0)
				y1 = y1 - (ny1 - cy1)
				out[#out + 1] = {
					image = quad.image, x = x0, y = cy0, w = x1 - x0, h = cy1 - cy0,
					u0 = quad.u0 + (x0 - quad.x) * fu, u1 = quad.u0 + (x1 - quad.x) * fu,
					v0 = quad.v0 + (y0 - quad.y) * fv, v1 = quad.v0 + (y1 - quad.y) * fv,
				}
			end
		end
	end
end

-- PlaneMaterial.getMaterialCellMatrix
local function matrixFor(material, normal)
	for _, m in ipairs(material.matrices) do
		if inRange(normal, m) then return m end
	end
	return nil
end

-- FloorRasterizer.render / WallRasterizer.render -> Plane.render -> PlaneVisualization.render ->
-- PlaneVisualizationLayer.render
function H.paintPlane(rc, kind, id, plane, size)
	local s = rc[kind]
	local p = s.planes[tostring(id)] or s.planes.default
	if not p then return nil end
	local v = visualizationFor(p, size or 64)
	if not v then return nil end
	local width, height = math.max(1, plane.textureWidth), math.max(1, plane.textureHeight)
	local normal = plane.normal
	-- PlaneVisualization.render starts from a texture filled white; the layers go on top of it
	local out = { width = width, height = height, layers = { { color = 0xFFFFFF, fill = true } } }
	for _, layer in ipairs(v.layers) do
		if layer.material then
			local m = matrixFor(layer.material, normal)
			if m then
				if plane.texture == false then
					-- no texture: a filled rectangle the layer's colour (createAndFillRenderTexture)
					out.layers[#out.layers + 1] = { color = layer.color, fill = true }
				else
					local quads = {}
					local c = layer.color
					local hasColor = (math.floor(c / 65536) % 256 < 255) or (math.floor(c / 256) % 256 < 255) or (c % 256 < 255)
					paintMatrix(quads, m, width, height, normal, plane.textureX or 0, plane.textureY or 0, layer.offset, layer.align == ALIGN_TOP, hasColor)
					out.layers[#out.layers + 1] = { color = layer.color, quads = quads }
				end
			end
		else
			out.layers[#out.layers + 1] = { color = layer.color, fill = true }
		end
	end
	return out
end
