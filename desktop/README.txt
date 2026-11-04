Bobba Hotel Desktop (test build)

Start Bobba Hotel.exe. The first time it asks for your garrysmod folder (it looks for it in your
Steam libraries itself); the hotel's gamemode, its addons and the Habbo files the game already
downloaded come from there. The hotel runs on this computer, like GMod's singleplayer.

  F1     the console (what the game prints; commands like bobba_give, bobba_status)
  F2     takes out / puts away the phone (the hotel's own look)
  F11    full screen (a borderless window the size of the screen)
  disconnect (in the console)   back to the start page

Your hotel (its database, your avatar picture) is kept in %APPDATA%\BobbaHotel\hotels\local.
The console's log is written to garrysmod\data\bobba_temp\desktop_console.log.

Made with LOVE (love2d.org, zlib licence: love-license.txt). Fonts: Ubuntu (Ubuntu Font
Licence), Lilita One and Plus Jakarta Sans (SIL Open Font Licence), in fonts/.

The hotel's Lua (the gamemode and its addons) runs with what Garry's Mod allows and no more: no
programs, no files outside garrysmod/data (for writing), no FFI.
