-- hotel/figureeditor.lua on a small made-up figuredata (the full check against nitro-react on Habbo's
-- own figuredata is tools/nitro-port/editor, with HABBO_DATA)
local T = {}
local FE = BOBBA.figureEditor

local function fd()
	local function colors(ids)
		local out = {}
		for i, c in ipairs(ids) do out[i] = { id = c[1], index = i, club = c[2] or 0, selectable = true, rgb = c[3] or 0x808080 } end
		return { colors = out }
	end
	local function set(id, gender, club, nColors, extra)
		local s = { id = id, gender = gender, club = club or 0, selectable = true, sellable = false, colorable = nColors > 0, parts = {} }
		s.parts[1] = { type = "x", id = id, index = 0, colorIndex = nColors > 0 and 1 or 0 }
		if nColors > 1 then s.parts[2] = { type = "x", id = id, index = 1, colorIndex = 2 } end
		for k, v in pairs(extra or {}) do s[k] = v end
		return s
	end
	local mand = function(m, f) return { M = { [0] = m, [1] = m }, F = { [0] = f, [1] = f } } end
	return {
		palettes = { [1] = colors({ { 1, 0, 0xFFCC99 }, { 2, 0 }, { 3, 2 } }), [3] = colors({ { 61, 0 }, { 62, 0 }, { 63, 1 } }) },
		order = { "hd", "hr", "ch", "lg", "ha" },
		setTypes = {
			hd = { paletteId = 1, mand = mand(true, true), sets = { set(180, "M", 0, 1), set(600, "F", 0, 1), set(185, "U", 1, 1) } },
			hr = { paletteId = 3, mand = mand(false, false), sets = { set(100, "M", 0, 1), set(515, "F", 0, 1), set(110, "U", 0, 2) } },
			ch = { paletteId = 3, mand = mand(true, true), sets = { set(210, "M", 0, 1), set(635, "F", 0, 1) } },
			lg = { paletteId = 3, mand = mand(true, true), sets = { set(270, "M", 0, 1), set(716, "F", 0, 2) } },
			ha = { paletteId = 3, mand = mand(false, false), sets = { set(1002, "U", 0, 1), set(1003, "U", 0, 1, { selectable = false }), set(1004, "U", 0, 1, { sellable = true }) } },
		},
	}
end

T["the editor opens on your look, the clothes for your gender, club clothes dimmed"] = function()
	local ed = FE.new(fd(), "hd-180-1.hr-100-61.ch-210-62.lg-270-61", "M", { clubLevel = 0 })
	eq(ed.figure:getFigureString(), "hd-180-1.hr-100-61.ch-210-62.lg-270-61")
	local hr = ed:model("head").byName.hr
	-- a "nothing" first (hair isn't mandatory), then the sets for boys and everyone
	eq(hr.parts[1].isClear, true)
	local ids = {}
	for i = 2, #hr.parts do ids[#ids + 1] = hr.parts[i].id end
	eq(table.concat(ids, ","), "100,110", "what you can wear first, then by id (Nitro's noob sorter)")
	eq(hr:getCurrentPart().id, 100, "your hair chosen")
	local hd = ed:model("generic").byName.hd
	eq(hd.parts[1].isClear, false, "the face is mandatory: no nothing")
	eq(hd.parts[1].id, 180, "what you can wear first")
	eq(hd.parts[2].id, 185, "club after it")
	eq(hd.parts[2].isDisabled, true, "and dimmed without club")
	local ha = ed:model("head").byName.ha
	eq(#ha.parts, 2, "hats: nothing, 1002 (not the unselectable one, not the sellable one)")
end

T["choosing: a piece, its colours, nothing, club things refused"] = function()
	local ed = FE.new(fd(), "hd-180-1.hr-100-61.ch-210-62.lg-270-61", "M")
	ed:selectPart("head", "hr", 2) -- (0-based: 110, two colours)
	eq(ed.figure:getPartSetId("hr"), 110)
	ed:selectColor("head", "hr", 1, 1)
	eq(ed.figure:getFigureString(), "hd-180-1.hr-110-61-62.ch-210-62.lg-270-61")
	eq(ed:selectColor("head", "hr", 2, 0), false, "a club colour can't be chosen")
	ed:selectPart("head", "hr", 0)
	eq(ed.figure:getFigureString(), "hd-180-1.ch-210-62.lg-270-61", "no hair")
	eq(ed:selectPart("generic", "hd", 1), false, "club face refused")
	eq(ed.figure:getPartSetId("hd"), 180)
end

T["Habbo's other order: club clothes first"] = function()
	FE.CLUB_ITEMS_FIRST = true
	local ed = FE.new(fd(), "hd-180-1.hr-100-61.ch-210-62.lg-270-61", "M", { clubLevel = 0 })
	local hd, hr = ed:model("generic").byName.hd, ed:model("head").byName.hr
	FE.CLUB_ITEMS_FIRST = false
	eq(hd.parts[1].id, 185, "club first (Nitro's club sorter)")
	eq(hr.parts[2].id .. "," .. hr.parts[3].id, "110,100", "highest id first")
end

T["gender, clear, reset and random"] = function()
	local ed = FE.new(fd(), "hd-180-1.hr-100-61.ch-210-62.lg-270-61", "M")
	ed:setGender("F")
	eq(ed.figure.gender, "F")
	eq(ed.figure:getFigureString(), FE.DEFAULT_FEMALE_FIGURE:gsub("hr%-515%-33", "hr-515-33"), "the girls' default")
	ed:setGender("M")
	eq(ed.figure:getFigureString(), "hd-180-1.hr-100-61.ch-210-62.lg-270-61", "your look again")
	ed:clear()
	eq(ed.figure:getFigureString(), "hd-180-1", "only the face")
	ed:reset()
	eq(ed.figure:getFigureString(), "hd-180-1.hr-100-61.ch-210-62.lg-270-61")
	local n = 0
	FE.random = function() n = n + 1 return ((n * 0.37) % 1) end
	ed:randomize()
	local f = ed.figure:getFigureString()
	assert(f:find("^hd%-180%-1"), "the face is kept: " .. f)
	assert(f:find("ch%-210") and f:find("lg%-270"), "the mandatory ones are there: " .. f)
	FE.random = math.random
end

return T
