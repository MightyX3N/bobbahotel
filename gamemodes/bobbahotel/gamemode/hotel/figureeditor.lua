-- The avatar editor's logic, ported from nitro-react (src/api/avatar: FigureData, CategoryData,
-- CategoryBaseModel, BodyModel, HeadModel, TorsoModel, LegModel, AvatarEditorUtilities,
-- AvatarEditorGridPartItem, AvatarEditorGridColorItem, FigureGenerator; github.com/billsonnn/
-- nitro-react, GPL-3), line by line. Plain Lua: no drawing here (client/avatareditor.lua draws it).
--
-- It works on figure data in this shape (bobba_habbo reads Habbo's figuredata into it):
--   fd.palettes[id] = { colors = { { id, index, club, selectable, rgb }, ... } }
--   fd.setTypes[type] = { paletteId, mand = { M = { [0] = bool, [1] = bool }, F = ... },
--                         sets = { { id, gender, club, selectable, sellable, colorable,
--                                    parts = { { type, id, index, colorIndex }, ... } }, ... } }
--   fd.order = { set types in figuredata's order }
--
--   local ed = BOBBA.figureEditor.new(fd, figure, gender, { clubLevel = 0, ownedSets = {} })
--   ed.categories = { "generic", "head", "torso", "legs" } and ed.models[name]
--   model.categories = { "hr", "ha", ... } and model.byName[name] = category
--   category.parts (part items), category.palettes[1..2] (colour items)
--   ed:selectPart(modelName, categoryName, index), ed:selectColor(modelName, categoryName, index, palette)
--   ed:setGender("M" | "F"), ed:clear(), ed:reset(), ed:randomize(), ed.figure:getFigureString()

BOBBA.figureEditor = BOBBA.figureEditor or {}
local FE = BOBBA.figureEditor

FE.MALE, FE.FEMALE, FE.UNISEX = "M", "F", "U"
FE.FACE, FE.HAIR, FE.HAT, FE.HEAD_ACCESSORIES = "hd", "hr", "ha", "he"
FE.EYE_ACCESSORIES, FE.FACE_ACCESSORIES, FE.JACKET, FE.SHIRT = "ea", "fa", "cc", "ch"
FE.CHEST_ACCESSORIES, FE.CHEST_PRINTS, FE.TROUSERS, FE.SHOES, FE.TROUSER_ACCESSORIES = "ca", "cp", "lg", "sh", "wa"
-- FigureData.SET_TYPES (trousers twice and no trouser accessories: as in Nitro)
FE.SET_TYPES = { "hd", "hr", "ha", "he", "ea", "fa", "cc", "ch", "ca", "cp", "lg", "sh", "lg" }
local SAVED_TYPES = { hd = true, hr = true, ha = true, he = true, ea = true, fa = true, ch = true, cc = true, ca = true, cp = true, lg = true, sh = true, wa = true }

-- nitro-react's AvatarEditorView
FE.DEFAULT_MALE_FIGURE = "hr-100.hd-180-7.ch-215-66.lg-270-79.sh-305-62.ha-1002-70.wa-2007"
FE.DEFAULT_FEMALE_FIGURE = "hr-515-33.hd-600-1.ch-635-70.lg-716-66-62.sh-735-68"
FE.MAX_PALETTES = 2
-- avatareditor.show.clubitems.first / .dimmed (Habbo's settings: here the clothes you can wear come
-- first, the club ones after them, so nobody scrolls past what they can't use to find what they can)
FE.CLUB_ITEMS_FIRST = false
FE.CLUB_ITEMS_DIMMED = true

FE.random = math.random

function FE.getGender(g)
	if g == "F" or g == "f" then return "F" end
	return "M"
end

-- --- FigureData ---------------------------------------------------------------------------------
local Figure = {}
Figure.__index = Figure

function FE.newFigure(fd, owner)
	return setmetatable({ fd = fd, owner = owner, data = {}, keys = {}, colors = {}, gender = "M", direction = 4 }, Figure)
end

function Figure:loadAvatarData(figure, gender)
	self.data, self.keys, self.colors = {}, {}, {}
	self.gender = gender
	if figure and figure ~= "" then
		for set in (figure .. "."):gmatch("([^%.]*)%.") do
			local parts = {}
			for v in (set .. "-"):gmatch("([^%-]*)%-") do parts[#parts + 1] = v end
			if #parts > 0 and set ~= "" then
				local setType = parts[1]
				local setId = tonumber(parts[2]) or -1
				local colorIds = {}
				for i = 3, #parts do colorIds[#colorIds + 1] = tonumber(parts[i]) or 0 end
				if #colorIds == 0 then colorIds[1] = 0 end
				self:savePartSetId(setType, setId)
				self:savePartSetColourId(setType, colorIds)
			end
		end
	end
end

function Figure:getPartSetId(setType)
	local v = self.data[setType]
	if v ~= nil then return v end
	return -1
end

function Figure:getColorIds(setType)
	local v = self.colors[setType]
	if v ~= nil then return v end
	return { FE.firstSelectableColor(self.fd, setType, self.owner and self.owner.clubLevel or 0) }
end

function Figure:getFigureString()
	local out = {}
	for _, setType in ipairs(self.keys) do
		local s = setType .. "-" .. self.data[setType]
		for _, c in ipairs(self.colors[setType] or {}) do s = s .. "-" .. c end
		out[#out + 1] = s
	end
	return table.concat(out, ".")
end

function Figure:savePartData(setType, partId, colorIds)
	self:savePartSetId(setType, partId)
	self:savePartSetColourId(setType, colorIds)
end

function Figure:savePartSetId(setType, partId)
	if not SAVED_TYPES[setType] then return end
	if partId >= 0 then
		if self.data[setType] == nil then self.keys[#self.keys + 1] = setType end
		self.data[setType] = partId
	elseif self.data[setType] ~= nil then
		self.data[setType] = nil
		for i, k in ipairs(self.keys) do if k == setType then table.remove(self.keys, i) break end end
	end
end

function Figure:savePartSetColourId(setType, colorIds)
	if not SAVED_TYPES[setType] then return end
	self.colors[setType] = colorIds
end

-- just the face (with face k, or the figure's own when override is false)
function Figure:getFigureStringWithFace(k, override)
	if override == nil then override = true end
	local colors = self.colors[FE.FACE]
	if not colors then return "" end
	local setId = self.data[FE.FACE]
	if override then setId = k end
	local s = FE.FACE .. "-" .. tostring(setId)
	if setId and setId >= 0 then for _, c in ipairs(colors) do s = s .. "-" .. c end end
	return s
end

-- --- AvatarEditorUtilities ------------------------------------------------------------------------
function FE.firstSelectableColor(fd, name, clubLevel)
	local t = fd.setTypes[name]
	if not t then return -1 end
	local palette = fd.palettes[t.paletteId]
	if not palette then return -1 end
	for _, c in ipairs(palette.colors) do
		if c.selectable and clubLevel >= c.club then return c.id end
	end
	return -1
end

-- the set types everyone of this gender has to wear (AvatarStructure.getMandatorySetTypeIds)
function FE.mandatorySetTypes(fd, gender, clubLevel)
	local out = {}
	for _, name in ipairs(fd.order or {}) do
		local t = fd.setTypes[name]
		if t and t.mand and t.mand[gender:upper()] and t.mand[gender:upper()][math.min(clubLevel, 1)] then out[#out + 1] = name end
	end
	return out
end

local function contains(list, v)
	for _, x in ipairs(list) do if x == v then return true end end
	return false
end

-- AvatarEditorGridPartItem (without the picture: client/avatareditor.lua draws it)
local function newPartItem(partSet, partColors, useColors, isDisabled)
	local item = { partSet = partSet, partColors = partColors, useColors = useColors, isDisabled = isDisabled or false,
		maxColorIndex = 0, isHC = false, isSellable = false, isClear = false, isSelected = false }
	if partSet then
		for _, p in ipairs(partSet.parts or {}) do item.maxColorIndex = math.max(item.maxColorIndex, p.colorIndex or 0) end
		item.isHC = (partSet.club or 0) > 0
		item.isSellable = partSet.sellable and true or false
	end
	item.id = partSet and partSet.id or -1
	return item
end

local function newColorItem(partColor, isDisabled)
	return { partColor = partColor, isDisabled = isDisabled or false, isHC = (partColor.club or 0) > 0, isSelected = false, color = partColor.rgb }
end

-- clubSorter / noobSorter / colorSorter, as "a comes before b"
local BIG = 9999999999
local function clubSorter(a, b)
	local ca, cb = a.partSet and a.partSet.club or BIG, b.partSet and b.partSet.club or BIG
	local sa, sb = a.partSet and a.partSet.sellable or false, b.partSet and b.partSet.sellable or false
	if sa and not sb then return false end
	if sb and not sa then return true end
	if ca ~= cb then return ca > cb end
	if not a.partSet or not b.partSet then return false end
	return a.partSet.id > b.partSet.id
end
local function noobSorter(a, b)
	local ca, cb = a.partSet and a.partSet.club or -1, b.partSet and b.partSet.club or -1
	local sa, sb = a.partSet and a.partSet.sellable or false, b.partSet and b.partSet.sellable or false
	if sa and not sb then return false end
	if sb and not sa then return true end
	if ca ~= cb then return ca < cb end
	if not a.partSet or not b.partSet then return false end
	return a.partSet.id < b.partSet.id
end
local function colorSorter(a, b)
	local ca, cb = a.partColor and a.partColor.club or -1, b.partColor and b.partColor.club or -1
	if ca ~= cb then return ca < cb end
	return (a.partColor.index or 0) < (b.partColor.index or 0)
end

-- a stable sort (Array.prototype.sort is stable)
local function stableSort(list, less)
	for i, v in ipairs(list) do v._order = i end
	table.sort(list, function(a, b)
		if less(a, b) then return true end
		if less(b, a) then return false end
		return a._order < b._order
	end)
end

-- --- CategoryData -------------------------------------------------------------------------------
local Category = {}
Category.__index = Category

function FE.createCategory(ed, name)
	local fd, figure = ed.fd, ed.figure
	local setType = fd.setTypes[name]
	if not setType then return nil end
	local palette = fd.palettes[setType.paletteId]
	if not palette then return nil end
	local partItems, colorItems = {}, {}
	for i = 1, FE.MAX_PALETTES do colorItems[i] = {} end
	local colorIds = figure:getColorIds(name) or {}
	local partColors = {}
	local level = ed.clubLevel
	for _, c in ipairs(palette.colors) do
		if c.selectable and (FE.CLUB_ITEMS_DIMMED or level >= c.club) then
			for i = 1, FE.MAX_PALETTES do
				colorItems[i][#colorItems[i] + 1] = newColorItem(c, level < c.club)
			end
			if name ~= FE.FACE then
				for i, cid in ipairs(colorIds) do if c.id == cid then partColors[i] = c end end
			end
		end
	end
	local mandatory = FE.mandatorySetTypes(fd, figure.gender, FE.CLUB_ITEMS_DIMMED and 2 or level)
	if not contains(mandatory, name) then
		local clear = newPartItem(nil, nil, false)
		clear.isClear = true
		partItems[#partItems + 1] = clear
	end
	local usesColors = name ~= FE.FACE
	for i = #setType.sets, 1, -1 do
		local set = setType.sets[i]
		local validGender = set.gender == FE.UNISEX or set.gender == figure.gender
		if set.selectable and validGender and (FE.CLUB_ITEMS_DIMMED or level >= set.club) then
			local valid = true
			if set.sellable then valid = ed.ownedSets[set.id] and true or false end
			if valid then partItems[#partItems + 1] = newPartItem(set, partColors, usesColors, level < set.club) end
		end
	end
	stableSort(partItems, FE.CLUB_ITEMS_FIRST and clubSorter or noobSorter)
	for i = 1, FE.MAX_PALETTES do stableSort(colorItems[i], colorSorter) end
	return setmetatable({ name = name, parts = partItems, palettes = colorItems, selectedPartIndex = -1, paletteIndexes = nil }, Category)
end

-- (Lua indexes from 1; Nitro's partIndex and paletteId from 0: kept from 0 here too)
function Category:selectPartId(partId)
	for i, item in ipairs(self.parts) do
		if item.id == partId then self:selectPartIndex(i - 1) return end
	end
end

function Category:selectColorIds(colorIds)
	if not colorIds then return end
	-- (JS: new Array(colorIds.length): that long even where nothing gets set)
	self.paletteIndexes = { n = #colorIds }
	for i = 0, #self.palettes - 1 do
		local palette = self:getPalette(i)
		if palette then
			local colorId = 0
			if #colorIds > i then
				colorId = colorIds[i + 1]
			else
				local first = palette[1]
				if first and first.partColor then colorId = first.partColor.id end
			end
			for j, item in ipairs(palette) do
				if item.partColor.id == colorId then
					self:setPaletteIndex(i, j - 1)
					item.isSelected = true
				else
					item.isSelected = false
				end
			end
		end
	end
	self:updatePartColors()
end

function Category:selectPartIndex(partIndex)
	if self.selectedPartIndex >= 0 and #self.parts > self.selectedPartIndex then
		local item = self.parts[self.selectedPartIndex + 1]
		if item then item.isSelected = false end
	end
	if #self.parts > partIndex then
		local item = self.parts[partIndex + 1]
		if item then
			item.isSelected = true
			self.selectedPartIndex = partIndex
			return item
		end
	end
	return nil
end

function Category:selectColorIndex(colorIndex, paletteId)
	local palette = self:getPalette(paletteId)
	if not palette then return nil end
	-- (going back to a colour index that was never set: JS compares with undefined, which is false)
	if colorIndex ~= nil and #palette <= colorIndex then return nil end
	self:deselectColorIndex(self.paletteIndexes[paletteId], paletteId)
	self:setPaletteIndex(paletteId, colorIndex)
	local item = colorIndex and palette[colorIndex + 1]
	if not item then return nil end
	item.isSelected = true
	self:updatePartColors()
	return item
end

function Category:getCurrentColorIndex(k) return self.paletteIndexes[k] end

function Category:deselectColorIndex(colorIndex, paletteIndex)
	local palette = self:getPalette(paletteIndex)
	if not palette or not colorIndex or #palette <= colorIndex then return end
	local item = palette[colorIndex + 1]
	if item then item.isSelected = false end
end

-- a palette's selected index (and the JS array's length: setting index k makes it at least k + 1)
function Category:setPaletteIndex(k, v)
	self.paletteIndexes[k] = v
	if k + 1 > self.paletteIndexes.n then self.paletteIndexes.n = k + 1 end
end

-- how many palette indexes there are (JS: the array's length)
local function indexCount(t)
	return t and t.n or 0
end

function Category:getSelectedColorIds()
	if not self.paletteIndexes or indexCount(self.paletteIndexes) == 0 then return nil end
	if #self.palettes == 0 then return nil end
	local first = self.palettes[1][1]
	if not first or not first.partColor then return nil end
	local colorId = first.partColor.id
	local ids = {}
	for i = 0, indexCount(self.paletteIndexes) - 1 do
		local paletteSet = self.palettes[i + 1]
		if paletteSet and #paletteSet > i then
			local idx = self.paletteIndexes[i]
			if idx and #paletteSet > idx then
				local c = paletteSet[idx + 1]
				ids[#ids + 1] = (c and c.partColor) and c.partColor.id or colorId
			else
				ids[#ids + 1] = colorId
			end
		end
	end
	local part = self:getCurrentPart()
	if not part then return nil end
	local out = {}
	for i = 1, math.min(#ids, math.max(part.maxColorIndex, 1)) do out[i] = ids[i] end
	return out
end

function Category:getSelectedColors()
	local out = {}
	for i = 0, indexCount(self.paletteIndexes) - 1 do
		local item = self:getSelectedColor(i)
		out[i + 1] = item and item.partColor or false
	end
	return out
end

function Category:getSelectedColor(paletteId)
	local palette = self:getPalette(paletteId)
	local idx = self.paletteIndexes and self.paletteIndexes[paletteId]
	if not palette or idx == nil or #palette <= idx then return nil end
	return palette[idx + 1]
end

function Category:getPalette(paletteId)
	if not self.paletteIndexes or #self.palettes <= paletteId then return nil end
	return self.palettes[paletteId + 1]
end

function Category:getCurrentPart()
	return self.parts[self.selectedPartIndex + 1]
end

function Category:updatePartColors()
	local colors = self:getSelectedColors()
	for _, item in ipairs(self.parts) do item.partColors = colors end
end

-- --- the models (CategoryBaseModel and its four) ----------------------------------------------------
local Model = {}
Model.__index = Model

FE.MODELS = {
	{ name = "generic", categories = { "hd" }, canSetGender = true },
	{ name = "head", categories = { "hr", "ha", "he", "ea", "fa" } },
	{ name = "torso", categories = { "ch", "cp", "cc", "ca" } },
	{ name = "legs", categories = { "lg", "sh", "wa" } },
}

-- (like Nitro, a model makes its categories when it's first shown: model.init())
local function newModel(ed, def)
	return setmetatable({ ed = ed, def = def, name = def.name, canSetGender = def.canSetGender or false, maxPaletteCount = 0 }, Model)
end

function Model:init()
	if self.categories then return end
	self.categories, self.byName = {}, {}
	for _, name in ipairs(self.def.categories) do
		local c = FE.createCategory(self.ed, name)
		if c then
			self.categories[#self.categories + 1] = name
			self.byName[name] = c
			self:updateSelectionsFromFigure(name)
		end
	end
end

function Model:updateSelectionsFromFigure(name)
	local c = self.byName and self.byName[name]
	if not c then return end
	local figure = self.ed.figure
	c:selectPartId(figure:getPartSetId(name))
	c:selectColorIds(figure:getColorIds(name) or {})
end

function Model:selectPart(name, partIndex)
	self:init()
	local c = self.byName[name]
	if not c then return end
	local previous = c.selectedPartIndex
	c:selectPartIndex(partIndex)
	local item = c:getCurrentPart()
	if not item then return end
	if item.isDisabled then
		c:selectPartIndex(previous)
		return false
	end
	self.maxPaletteCount = item.maxColorIndex
	self.ed.figure:savePartData(name, item.id, c:getSelectedColorIds())
	return true
end

function Model:selectColor(name, colorIndex, paletteId)
	self:init()
	local c = self.byName[name]
	if not c then return end
	local previous = c:getCurrentColorIndex(paletteId)
	c:selectColorIndex(colorIndex, paletteId)
	local item = c:getSelectedColor(paletteId)
	if not item then return end
	if item.isDisabled then
		c:selectColorIndex(previous, paletteId)
		return false
	end
	self.ed.figure:savePartSetColourId(name, c:getSelectedColorIds())
	-- BodyModel: the faces' pictures follow the skin colour
	if self.name == "generic" then self:updateSelectionsFromFigure(FE.FACE) end
	return true
end

-- --- the editor (AvatarEditorView's state) ----------------------------------------------------------
local Editor = {}
Editor.__index = Editor

function FE.new(fd, figure, gender, opts)
	opts = opts or {}
	local ed = setmetatable({ fd = fd, clubLevel = opts.clubLevel or 0, ownedSets = opts.ownedSets or {}, figures = {} }, Editor)
	local male, female = FE.newFigure(fd, ed), FE.newFigure(fd, ed)
	male:loadAvatarData(FE.DEFAULT_MALE_FIGURE, FE.MALE)
	female:loadAvatarData(FE.DEFAULT_FEMALE_FIGURE, FE.FEMALE)
	ed.figures[FE.MALE], ed.figures[FE.FEMALE] = male, female
	ed.figure = male
	ed:resetCategories()
	if figure then ed:load(figure, gender, true) end
	return ed
end

function Editor:resetCategories()
	self.models = {}
	self.categories = {}
	for _, def in ipairs(FE.MODELS) do
		self.models[def.name] = newModel(self, def)
		self.categories[#self.categories + 1] = def.name
	end
end

-- a model, made ready to show (ModelView: model.init())
function Editor:model(name)
	local m = self.models[name]
	if m then m:init() end
	return m
end

-- a new FigureData: the models are made again (AvatarEditorView: useEffect on figureData)
function Editor:setFigure(f)
	self.figure = f
	self:resetCategories()
end

-- loadAvatarInEditor
function Editor:load(figure, gender, reset)
	gender = FE.getGender(gender)
	local f = self.figure
	if gender ~= f.gender then f = self.figures[gender] end
	if figure ~= f:getFigureString() then f:loadAvatarData(figure, gender) end
	if f ~= self.figure then self:setFigure(f) end
	if reset then
		self.lastFigure = self.figure:getFigureString()
		self.lastGender = self.figure.gender
	end
end

function Editor:setGender(gender)
	self:setFigure(self.figures[FE.getGender(gender)])
end

function Editor:selectPart(modelName, name, partIndex)
	local m = self.models[modelName]
	return m and m:selectPart(name, partIndex)
end

function Editor:selectColor(modelName, name, colorIndex, paletteId)
	local m = self.models[modelName]
	return m and m:selectColor(name, colorIndex, paletteId)
end

-- the actions under the preview
function Editor:clear()
	self:load(self.figure:getFigureStringWithFace(0, false), self.figure.gender, false)
	self:resetCategories()
end
function Editor:reset()
	self:load(self.lastFigure, self.lastGender, true)
	self:resetCategories()
end
function Editor:randomize()
	self:load(FE.randomFigure(self.fd, self.figure, self.figure.gender, self.clubLevel, self.ownedSets, { FE.FACE }), self.figure.gender, false)
	self:resetCategories()
end

function Editor:rotate(direction)
	if direction < 0 then direction = 7 + (direction + 1) end
	if direction > 7 then direction = direction - 8 end
	self.figure.direction = direction
end

-- --- FigureGenerator ------------------------------------------------------------------------------
-- Randomizer.getRandomElements: count different elements
local function randomElements(list, count)
	local result, len, taken = {}, #list, {}
	while count > 0 do
		count = count - 1
		local x = math.floor(FE.random() * len)
		result[count + 1] = list[(taken[x] or x) + 1]
		len = len - 1
		taken[x] = taken[len] or len
	end
	return result
end

function FE.randomFigure(fd, figure, gender, clubLevel, owned, ignoredSets)
	clubLevel = clubLevel or 0
	owned = owned or {}
	local required = FE.mandatorySetTypes(fd, gender, clubLevel)
	local options = {}
	for _, t in ipairs(FE.SET_TYPES) do if not contains(required, t) then options[#options + 1] = t end end
	local picked = randomElements(options, math.floor(FE.random() * #options) + 1)
	for _, t in ipairs(picked) do required[#required + 1] = t end
	local parts, order = {}, {}
	local function update(t, id, colors)
		if not parts[t] then order[#order + 1] = t end
		parts[t] = { id = id, colors = colors }
	end
	for _, t in ipairs(ignoredSets or {}) do update(t, figure:getPartSetId(t), figure:getColorIds(t)) end
	for _, t in ipairs(required) do
		local setType = fd.setTypes[t]
		if not parts[t] and setType then
			local choices = {}
			for _, set in ipairs(setType.sets) do
				if set.selectable and (set.gender == "U" or set.gender == gender) and set.club <= clubLevel and not (set.sellable and not owned[set.id]) then
					choices[#choices + 1] = set
				end
			end
			if #choices > 0 then
				local set = choices[math.floor(FE.random() * #choices) + 1]
				local colors = {}
				if set.colorable then
					local palette = fd.palettes[setType.paletteId]
					local colorChoices = {}
					for _, c in ipairs(palette and palette.colors or {}) do
						if c.selectable and c.club <= clubLevel then colorChoices[#colorChoices + 1] = c end
					end
					local total = 0
					for _, p in ipairs(set.parts) do total = math.max(total, p.colorIndex or 0) end
					for _, c in ipairs(randomElements(colorChoices, total)) do colors[#colors + 1] = c.id end
				end
				update(t, set.id, colors)
			end
		end
	end
	-- AvatarFigureContainer.getFigureString
	local out = {}
	for _, t in ipairs(order) do
		local p = parts[t]
		local s = t .. "-" .. p.id
		for _, c in ipairs(p.colors or {}) do s = s .. "-" .. c end
		out[#out + 1] = s
	end
	return table.concat(out, ".")
end
