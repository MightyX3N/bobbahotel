-- Letters a font doesn't have (symbols, other alphabets, emoji in a Steam name) are taken from the
-- system's fonts, as Windows does for GMod: FB.apply(font, size) gives a Love font its fallbacks.
local FS = require("bobba.fs")
local FB = {}
local files

local function list()
	if files then return files end
	files = {}
	local candidates
	if FS.windows then
		local dir = (os.getenv("WINDIR") or "C:/Windows"):gsub("\\", "/") .. "/Fonts/"
		candidates = {}
		for _, f in ipairs({ "segoeui.ttf", "seguisym.ttf", "seguiemj.ttf", "arial.ttf", "malgun.ttf", "msyh.ttc", "msgothic.ttc", "Nirmala.ttf", "seguihis.ttf" }) do
			candidates[#candidates + 1] = dir .. f
		end
	else
		candidates = { "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/TTF/DejaVuSans.ttf", "/usr/share/fonts/truetype/noto/NotoSansSymbols2-Regular.ttf" }
	end
	for _, p in ipairs(candidates) do
		local bytes = FS.read(p)
		if bytes then
			local ok, data = pcall(love.filesystem.newFileData, bytes, p:match("[^/]+$"))
			if ok then files[#files + 1] = data end
		end
	end
	return files
end

local made = {}
function FB.apply(font, size)
	size = math.max(1, math.floor(size + 0.5))
	if not made[size] then
		made[size] = {}
		for _, data in ipairs(list()) do
			local ok, f = pcall(love.graphics.newFont, data, size)
			if ok then made[size][#made[size] + 1] = f end
		end
	end
	if #made[size] > 0 then pcall(font.setFallbacks, font, unpack(made[size])) end
	return font
end

return FB
