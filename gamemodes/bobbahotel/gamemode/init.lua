AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
-- the hotel's font (Nitro's: Ubuntu Condensed, Ubuntu Font Licence; in addons/bobbahotel), sent to
-- players who don't have it (GMod loads it when the game starts)
resource.AddFile("resource/fonts/UbuntuCondensed-Regular.ttf")
resource.AddFile("resource/fonts/LilitaOne-Regular.ttf")
-- the phone's font (Plus Jakarta Sans, SIL Open Font Licence; also in addons/bobbahotel)
for _, w in ipairs({ "Medium", "Bold", "ExtraBold" }) do resource.AddFile("resource/fonts/PlusJakartaSans-" .. w .. ".ttf") end
include("shared.lua")
