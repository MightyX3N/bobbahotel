# bobbahotel (the gamemode's own addon)

What the gamemode needs outside `gamemodes/bobbahotel/`: GMod only loads fonts from `resource/fonts/`
in an addon (at game start), not from a gamemode's folder.

- `resource/fonts/UbuntuCondensed-Regular.ttf`: the hotel's font, Nitro's "Ubuntu" (Ubuntu Font
  Licence 1.0, `UbuntuFontLicence.txt`). Servers send it to players (`resource.AddFile` in `init.lua`).

Copy this folder to `garrysmod/addons/bobbahotel/`.
