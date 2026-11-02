# Bobba Hotel (web) – build list

Everything the Garry's Mod gamemode had, in the order it gets built. `[x]` = done in the web version.

## 1. Core hotel
- [x] Isometric rooms from layouts (41 layouts), floors/walls from sprites, raised floors
- [x] Click-to-walk (A*, 8 directions, height steps), walk animation
- [x] Layered Cozy avatar (body, hair, top, bottom, shoes), wardrobe window, saved looks
- [x] Chat bubbles
- [x] Public rooms (Lobby, Café, Rooftop, Plaza) and guest rooms (create, 10 per player)
- [x] Room browser window, create-room window, help window, HUD toolbar
- [x] Steam login + guest play, admin panel, auto-deploy
- [ ] Chat filter ("bobba" for swear words / personal info)
- [ ] Chat commands (`:help :sit :stand :wave :newlook :rooms :goto :hotel`, staff `:news`)
- [ ] Wave, sit on the floor, AFK (ZZZ)
- [ ] Zoom and pan (wheel / drag), rooms open zoomed in
- [ ] Hotel view / login screen with fake-login animation (skippable)

## 2. Furniture (880 sprites)
- [x] Furni definitions (size from sprite, rotation, stack/top height, seat/bed flags, price, shop page)
- [x] Draw furni in rooms with correct depth sorting
- [x] Place / move / rotate / pick up (click to select, ghost preview, R rotates); owner-only for now
- [ ] Drag-to-move, room rights for other players
- [x] Stacking on tables, "can't pick up while something is on it"
- [x] Sitting on chairs/sofas (double-click or walk onto them)
- [ ] Lying in beds (2x2 beds fit two)
- [ ] Wall items (windows, posters, shelves) - 77 pieces, hidden from the shop until wall placement exists
- [x] Walkable stairs, walkable rugs
- [x] Double-click toggles (lamps, TVs, lava lamp, animated machines)
- [ ] Teleporters with linking, room picker showing layouts
- [ ] Dice
- [ ] Wired (room logic) – later

## 3. Economy and shop
- [x] Silver and gold coins (100 silver = 1 gold), balance in the HUD
- [x] Inventory window ("My stuff"), place from inventory
- [x] Catalogue window: Furni pages (by kind and by room), bundles
- [ ] Catalogue: Front Page, Clothing, Pets, Memberships tabs
- [x] Buy flow: buy -> My stuff -> place; bundles
- [ ] Vouchers, room events
- [ ] Gifts (furni and coins), opened visibly in the room
- [ ] Coins as physical items
- [ ] Bobba Club (buy with gold, gift days, admin grant, club-only layouts)
- [ ] Trading between players – later

## 4. Social
- [ ] Friends list, requests, messenger, follow
- [ ] Profile / avatar info card, "change look" from your own avatar
- [ ] Room settings (name, description, floor, wall, door, access: open / locked / key, max users)
- [ ] Room rights (give/remove), kick/mute/ban in a room
- [ ] Room events, popular rooms, search, friends' rooms
- [ ] Up to 3 accounts per Steam account

## 5. Pets
- [ ] Cats from the pack, buy, place, walk around, interact

## 6. Content and polish
- [ ] News (staff `:news`), shown in hotel view and on playbobba.com
- [ ] Localisation (English, Danish), all UI text in language files
- [ ] Admin: give coins, give furni, edit public rooms, build public rooms
- [ ] Themes (base Bobba, R63B, Origins)
- [ ] Screenshot camera
- [ ] playbobba.com community site (login, groups, news, avatar)

## Licence checks
- [ ] Cozy Assets (Klimmos) licence for web use
