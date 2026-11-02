# Roadmap

A step is ticked only after it has been played on the live server. One step at a time.

## 1. Foundation
- [x] Repo setup: workspaces, `npm run dev`, `npm run check`, CI, auto-deploy with rollback, placeholder page live

## 2. First slice
- [x] Log in (Steam and guest); choosing between up to 3 accounts per Steam account comes later
- [x] Enter one room (real room drawing: floor, walls, door)
- [x] Walk (click to walk, pathfinding, 500 ms room tick)
- [x] See a second player walk and chat (chat bubbles)

## 3. Rooms and the UI foundation
- [x] UI foundation: React UI layer, theme folder (Bobba theme based on Nitro's UI), English language file with all UI text
- [x] Toolbar (with the chat input)
- [x] Navigator: public rooms, all rooms, my rooms, search
- [x] Create a room from the Habbo room layouts; move between rooms
- [x] Room drawing from Nitro's room code: walls, stairs, doorway; zoom

## 4. Layouts and Bobba Club
- [x] In-game layout editor (draw floor, heights, door), save new layouts; Club members reshape their own rooms
- [x] Bobba Club: Club-only layouts (incl. all of Habbo's standard layouts) and other extras, admin can grant Club time (`:club`)
- Donations moved to later (see the end)

## 5. Hotel systems, in order
- [ ] Furni: definitions, drawing, place / move / rotate / pick up, stacking, sitting
- [ ] Inventory ("My stuff")
- [ ] Catalogue and buying
- [ ] Coins (silver and gold)
- [ ] Room settings, rights
- [ ] Avatar looks (Cozy), wardrobe
- [ ] Chat filter, commands, wave, AFK
- [ ] Friends and messenger
- [ ] Gifts, teleporters, dice, pets, wired (later)
- [ ] Admin panel
- [ ] Credits page (pixel_Salvaje, Klimmos)

## Later
- [ ] Donations give Club time based on the amount (donation service tells the server automatically)
