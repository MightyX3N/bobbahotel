# Runs the same action script through the gamemode's hotel/figureeditor.lua (LuaJIT), on figuredata
# read by bobba_habbo's lib/figuredata.lua: one state per step, in the same shape as run_js.js
import json, os, sys
from lupa import luajit21 as lj
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
GM = os.path.join(ROOT, "gamemodes", "bobbahotel", "gamemode")
LIB = os.path.join(ROOT, "addons", "bobba_habbo", "lua", "bobbahotel", "addons", "bobba_habbo", "lib")
xml_path, script_path, out_path = sys.argv[1:4]
L = lj.LuaRuntime(unpack_returned_tuples=True)
L.globals().LIB_DIR = LIB
L.execute("""BOBBA = { platform = { httpGet = function() end, writeData = function() end, readData = function() end, dataExists = function() return false end,
    runAddonFile = function(f, n) return dofile(LIB_DIR .. "/" .. n:gsub("^lib/", "")) end } }""")
L.execute(open(os.path.join(LIB, "..", "shared.lua")).read())
L.execute(open(os.path.join(GM, "hotel", "figureeditor.lua")).read())
script = json.load(open(script_path))
L.globals().RANDOM = L.table_from(script["random"])
L.globals().SCRIPT = L.eval("function(s) return s end")(None)
L.globals().FD = L.eval("function(x) return BOBBA.habbo.parseFigureData(x) end")(open(xml_path, encoding="utf-8").read())
run = L.eval(r"""function(club, steps, clubFirst)
    local FE = BOBBA.figureEditor
    FE.CLUB_ITEMS_FIRST = clubFirst
    local r = 0
    FE.random = function() r = r + 1 return RANDOM[((r - 1) % #RANDOM) + 1] end
    local ed = FE.new(FD, nil, "M", { clubLevel = club })
    local states = {}
    local function arr(t, n) local o = {} for i = 1, n do o[i] = t[i] end return o end
    local function state()
        local out = { figure = ed.figure:getFigureString(), gender = ed.figure.gender, models = {} }
        for _, mname in ipairs(ed.categories) do
            local m = ed:model(mname)
            local cats = {}
            for _, cname in ipairs(m.categories) do
                local c = m.byName[cname]
                local parts = {}
                for i, p in ipairs(c.parts) do parts[i] = { p.id, p.isClear and 1 or 0, p.isDisabled and 1 or 0, p.isSelected and 1 or 0, p.maxColorIndex } end
                local pals = {}
                for i = 0, 1 do
                    local p = c:getPalette(i)
                    if p then
                        local o = {}
                        for j, x in ipairs(p) do o[j] = x.partColor.id * 4 + (x.isSelected and 1 or 0) + (x.isDisabled and 2 or 0) end
                        pals[i + 1] = o
                    else
                        pals[i + 1] = false
                    end
                end
                cats[cname] = { parts = parts, selected = c.selectedPartIndex, palettes = pals, colorIds = c:getSelectedColorIds() or false }
            end
            out.models[mname] = cats
        end
        return out
    end
    r = 0
    for _, s in ipairs(steps) do
        local ok, err = pcall(function()
            if s.op == "load" then ed:load(s.figure, s.gender, true)
            elseif s.op == "part" then
                local m = ed:model(s.model); local c = m.byName[s.cat]
                m:selectPart(s.cat, #c.parts > 0 and (s.index % #c.parts) or -1)
            elseif s.op == "color" then
                local m = ed:model(s.model); local c = m.byName[s.cat]; local p = c:getPalette(s.palette)
                if p and #p > 0 then m:selectColor(s.cat, s.index % #p, s.palette) end
            elseif s.op == "gender" then ed:setGender(s.gender)
            elseif s.op == "clear" then ed:clear()
            elseif s.op == "reset" then ed:reset()
            elseif s.op == "random" then ed:randomize() end
        end)
        states[#states + 1] = ok and state() or { error = tostring(err) }
    end
    return states
end""")
def py(x):
    if lj.lua_type(x) == "table":
        keys = list(x.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [py(x[k]) for k in sorted(keys)]
        if not keys: return []
        return {str(k): py(x[k]) for k in keys}
    if x is False: return None
    return x
states = []
for rn in script["runs"]:
    steps = L.table_from([L.table_from(s) for s in rn["steps"]])
    states += py(run(rn["club"], steps, rn.get("clubFirst", True)))
json.dump(states, open(out_path, "w"))
print("lua:", len(states), "states")
