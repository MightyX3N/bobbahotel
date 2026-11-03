-- A small XML reader for Habbo's data (furnidata, figuredata, figuremap and the XML inside the
-- SWF files). Gives a tree: { name = "tag", attrs = { ... }, children = { ... }, text = "..." }.
-- Plain Lua.
--   local root = BOBBA.habbo.xml.parse(text)
--   BOBBA.habbo.xml.find(root, "visualization")      first element with that name (any depth)
--   BOBBA.habbo.xml.all(root, "layer")               every element with that name (any depth)

local XML = {}

local ENTITIES = { lt = "<", gt = ">", amp = "&", quot = '"', apos = "'" }
local function unescape(s)
	return (s:gsub("&(#?x?)(%w+);", function(kind, v)
		if kind == "#" then return string.char(tonumber(v) % 256) end
		if kind == "#x" then return string.char(tonumber(v, 16) % 256) end
		return ENTITIES[v] or ("&" .. v .. ";")
	end))
end

local function attrs(s)
	local out = {}
	for k, q, v in s:gmatch("([%w_:%-%.]+)%s*=%s*([\"'])(.-)%2") do out[k] = unescape(v) end
	return out
end

function XML.parse(text)
	-- a byte order mark at the start is not part of the XML
	if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end
	local root = { name = "#document", attrs = {}, children = {} }
	local stack = { root }
	local pos = 1
	while true do
		local s = text:find("<", pos, true)
		if not s then break end
		local top = stack[#stack]
		if s > pos then
			local t = text:sub(pos, s - 1)
			if t:find("%S") then top.text = (top.text or "") .. unescape(t) end
		end
		if text:sub(s, s + 3) == "<!--" then
			local e = text:find("-->", s + 4, true)
			pos = (e or #text) + 3
		elseif text:sub(s, s + 8) == "<![CDATA[" then
			local e = text:find("]]>", s + 9, true)
			top.text = (top.text or "") .. text:sub(s + 9, (e or #text + 1) - 1)
			pos = (e or #text) + 3
		elseif text:sub(s, s + 1) == "<?" or text:sub(s, s + 1) == "<!" then
			local e = text:find(">", s, true)
			pos = (e or #text) + 1
		elseif text:sub(s, s + 1) == "</" then
			local e = text:find(">", s, true)
			if #stack > 1 then stack[#stack] = nil end
			pos = (e or #text) + 1
		else
			local e = text:find(">", s, true)
			if not e then break end
			local inner = text:sub(s + 1, e - 1)
			local selfClosing = inner:sub(-1) == "/"
			if selfClosing then inner = inner:sub(1, -2) end
			local name, rest = inner:match("^([%w_:%-%.]+)(.*)$")
			if name then
				local el = { name = name, attrs = attrs(rest or ""), children = {} }
				top.children[#top.children + 1] = el
				if not selfClosing then stack[#stack + 1] = el end
			end
			pos = e + 1
		end
	end
	return root
end

function XML.all(node, name, out)
	out = out or {}
	for _, c in ipairs(node.children or {}) do
		if c.name == name then out[#out + 1] = c end
		XML.all(c, name, out)
	end
	return out
end

function XML.find(node, name)
	for _, c in ipairs(node.children or {}) do
		if c.name == name then return c end
		local f = XML.find(c, name)
		if f then return f end
	end
	return nil
end

-- children with a name (one level)
function XML.children(node, name)
	local out = {}
	for _, c in ipairs(node.children or {}) do
		if not name or c.name == name then out[#out + 1] = c end
	end
	return out
end

return XML
