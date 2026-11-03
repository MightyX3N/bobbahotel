-- Bobba Hotel Desktop: the window and what Love starts
function love.conf(t)
	t.identity = "BobbaHotel"
	t.appendidentity = false
	t.version = "11.5"
	t.console = false
	t.window.title = "Bobba Hotel"
	t.window.icon = "icon.png"
	t.window.width = 1280
	t.window.height = 760
	t.window.minwidth = 1024
	t.window.minheight = 640
	t.window.resizable = true
	t.window.vsync = 1
	t.window.highdpi = false
	t.modules.physics = false
	t.modules.joystick = false
	t.modules.video = false
	t.modules.touch = false
end
