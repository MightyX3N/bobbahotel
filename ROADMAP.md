# Roadmap

What's done, what's next, and the ideas agreed for later, grouped under the part they belong to.
Nothing here is a promise of when; it keeps the plans in one place.

## Done

1. **The basics**: rooms drawn the way Nitro draws them, avatars, walking, chat, the toolbar, the
   catalogue, the inventory, wallet and club, gifts.
2. **Wall furni**: posters, stickies, mood lights, windows.
3. **Rooms** (mostly): the navigator, creating rooms, settings (access, rights, chat, moderation),
   the doorbell and passwords, kick / ban / mute, favourites and home rooms, the hotel view, the
   avatar menu and infostand, the chat settings, the navigator's room popover, the floor plan editor (Habbo Club, as in Habbo; the hotel can open it to
   everyone), starter rooms (a new player picks one; packs register their own), then a short tutorial in it
   (walk, open the gift, move or turn a furni, say something; 50 credits, tutorial.reward.credits).
   Still open for rooms:
   - the navigator's thumbnail view (a grid of the rooms' pictures)
   - report, word filter

**Free movement** is done: with the arrow keys or WASD (Settings: arrow keys / WASD while the chat is
empty / WASD with Enter to chat; directions as on the screen or along the room) or a controller's stick
(any angle) the avatar moves freely, at once on your own screen (the server checks every move: walking
speed, only over tiles one can walk on, a fifth of a tile off walls and furni, not out of the door);
everything else (wired, rollers, gates, the room's grid) goes by the tile under its middle; let go and
it eases onto that tile's middle (and sits there on a seat). Others see it glide. Clicking walks
Habbo's way as before. The interact button (Space, or E with WASD) uses what's next to you, with a
highlight and a list when there's more than one; the keys and the controller's buttons can be changed
(Settings > Keys and controller); a notification when a controller connects; the room's movement
setting (clicking and free movement / clicking only / free movement only) shown in the room info. The
desktop app reads controllers (stick or d-pad, A use, LB next, RB turn, right stick pointer with X / B,
Y menu wheel, Back quick messages, Start chat); in GMod a controller works through Steam Input.

The desktop app (Love2D, runs the gamemode without GMod) is working: launcher, hosting a hotel,
borderless full screen, its own icon.

**The phone and tablet** are the default UI (a pack can choose another: the Habbo pack keeps Nitro's;
`bobba_ui phone` / `habbo` or Settings picks for yourself): a phone (F2, or the button in the corner)
and a tablet with a lock screen, a home screen you arrange (apps, widgets, pages, the dock; saved per
hotel), the shade with quick tiles, notifications. Apps: Rooms, Bag, Wallet, Camera, Settings, three
shops (Furni; Clothes and effects; Club), the floor plan (tablet), Messages (friends, requests,
following), Groups (members, ranks, text and voice channels, a room per group), Calls (a dummy for now),
Events (room events in the navigator too), Videos and the App Store (a hotel's app addons). An app
without a tablet view shows as a phone on the tablet. After checking in, the hotel's own page (Lua:
the pack's or an addon's; the Habbo pack has a Habbo-style one), then the room. The desktop app opens
on a server picker; a hotel's Lua runs there sandboxed the way GMod limits it (no files outside data,
no FFI, no running programs).

**Managing the hotel**: its owner and admins (bobba.admin.hotel) have a Manage screen - from the start
screen, the hotel's page or the phone's Settings - for its addons (on or off from the next start, a
restart button), their settings (an addon describes them in its addon.lua), the hotel's own settings
(money, shops, groups, rooms...) and its look (name, about, news, the UI players start in, its colour,
which page shows). Garry's Mod has the start screen too when you host the game (singleplayer or a
listen server); joining someone's server goes straight to its page.

## Next

4. **Avatar**: done so far: dances (Habbo Club's four too), wave, blow a kiss, laugh, idle (asleep
   after two minutes of nothing, eyes closed; avatars blink), signs, sitting on the floor, avatar
   effects (owned with a time and a count, worn from the avatar editor's Effects tab, drawn with
   Habbo's effect pictures: hoverboards, spotlights, sparkles ...), the wardrobe (ten saved looks).
   Effects are given with `bobba_give <player> effect <id> [days]` until the catalogue sells them.
   The camera: Habbo's camera over the room (pictures of the room alone), a roll of five, buying a
   shot as a photo to hang on a wall (camera.price.credits, 2), room thumbnails from the room info
   (shown there and in the navigator).
   - later: the camera's filters and frames (Nitro's editor), publishing photos to the website
5. **Chat commands**.
6. **Friends and messenger**: done in the phone's Messages (requests, the messenger, following);
   still to do: Nitro's friends bar and messenger for the Habbo UI, and:
   - Steam friends who play the hotel are friends automatically; removing one removes them only in
     the hotel and puts them on a removed list so they aren't added again (unfriending is mutual);
     a note when a Steam friends list is private.
   - offline messages, "friend came online" notices
7. **Trading**, and the economy's safety:
   - every credit, purchase, trade and gift logged; limits on suspicious patterns (duplication,
     trade scams)
   - later: a marketplace like Habbo's
8. **Pets and bots**.
9. **Groups**: done in the phone (the server is shared); still to do: the Habbo UI's group windows.
10. **Rewards**: achievements, badges, daily quests, an advent calendar and seasonal events.
11. **Minigames and wired**.
    - games made for free movement (WASD / stick): laser tag (shoot the way you
      face, walls and furni block it, a hit stuns and scores, teams by colour), built from wired
      parts (a laser gun effect, a "hit by laser" trigger, team scores) so owners design their own
      arenas; the server decides hits. Banzai, Freeze and snowball fights play better this way too.
    - wired for movement: switch free movement or click-walking off (for a user, everyone, or users
      on tiles, optionally for a while) and back; conditions "is moving freely" / "is click-walking"
    - **Voice chat** (GMod first): heard in your room only, quieter with distance on the tiles
      (each player's game sets each speaker's volume).
      - each player chooses open mic or push-to-talk (the gamemode switches the microphone itself)
      - room settings: off / player's choice / push-to-talk only / open mic forced; who may talk
        (everyone, rights, the mic only)
      - forced open mic needs consent: a window at the door ("Enter with microphone on" / Cancel),
        asked every visit; switched on while people are inside, they get the same choice and nothing
        changes for them until they answer; leaving puts the mic back to their own setting; the
        change is written to the room's history
      - icons for the room's voice setting in the navigator and the room info; your own mic state in
        the room tools; a speaking icon over avatars
      - the stage microphone furni: whoever uses it is heard by the whole room at full volume
      - wired: voice off / voice volume (for users, or users on tiles: a quiet audience floor, a
        normal stage) / only the mic heard / reset; triggers "starts / stops talking", condition "is
        talking"; wired only ever lowers voices, never turns a microphone on, and a player's own mute
        always wins
      - moderation: room mutes apply to voice, per-person mute, a staff voice mute
      - the hotel owner can switch voice off for the whole hotel
    - **Text to speech** (each player switches it on for themselves): messages in your room read
      aloud, quieter with distance, a voice per avatar; a queue that skips when it falls behind;
      reads the filtered text only, not commands; whoever is at the stage mic is read to everyone.
      Providers: Windows' own speech in the desktop app, a URL the server owner sets on GMod, more
      from packs.
12. **Staff and admin**: the staff tools, reports, the word filter.
    - **Moderation helper** (the owner tunes it or turns it off: Off / Light / Standard / Strict;
      setting up a hotel asks "just friends or a public community?" to pick the start):
      - rules, no AI: personal info (phone numbers, emails, addresses, other platforms) masked;
        "add me on ...", "what's your number", "don't tell anyone", age questions flagged
      - an AI (a provider the owner picks: a hosted service, or a model on their own machine) reads
        only flagged conversations and tells staff why
      - the AI never acts on its own; staff decide
      - alerts by level: low (in the list), medium (a notice), critical (a pop-up for every staff
        member until someone takes it, repeating and getting louder, a Discord ping; if no staff
        are online it waits on top for the next one); others are told who took it
      - "false alarm" button and a count of false versus real alerts, so the critical level stays
        rare and trusted
      - players are told chat is checked (not when it's off); logs kept for a limited time; for
        child-safety cases the alert says to keep the evidence and report to the police
    - "download my data" and "delete my account" for players
13. **Custom server, web client, release**.
    - **Web client** on GitHub Pages, like the desktop app: the same gamemode code in the browser
      (the desktop client built for the web with love.js; what it does through LuaJIT's FFI gets
      browser versions), one address for every hotel with the hotel list
      - touch for phones and tablets: tap to walk and select, long-press for the right-click menu,
        drag to move the room, pinch to zoom, bigger hit areas, a small-screen layout
      - browsers only speak WebSockets: the custom server, or a bridge next to a GMod server (the
        egg can start it); secure WebSockets need a certificate (playit, a proxy, the panel)
      - check early whether browsers may download Habbo's files directly (CORS); if not, the
        hotel passes them through or caches them
      - profile on a mid-range phone
      - a hotel's own website opens it straight into that hotel; the GitHub Pages one is for
        players on several hotels (the hotel list, a login per hotel), on a tablet or any PC
    - **Android and iOS apps** (far future): Love2D runs on both, so mostly the desktop client again
      with the web client's touch; normal connections (no WebSocket bridge). Android first (an APK
      to install directly, Google Play later); iOS needs a Mac and Apple's developer account, and
      runs without LuaJIT's JIT (slower). The stores require a word filter, reporting, blocking
      and quick handling of abuse in chat apps (part 12 first).
    - **Hosting**:
      - a Pterodactyl egg (GMod first, the custom server later); panel variables for the hotel's
        name, owner and staff Steam IDs, public or friends, max players, start credits, Discord, the
        content pack; a save on the panel's stop signal so backups are never half written
      - multiple hotels are separate servers in the panel (no hotel manager of our own)
      - optional playit.gg in the egg: a secret key variable, the agent tunnels the game port, the
        hotel shows that address (the server then sees playit's address, not players' IPs: nothing
        may rely on IPs)
      - hotel addresses by name in our own clients: the client looks the hotel up on its domain
        and connects to wherever it really is
      - a public list of hotels for the launcher (optional, later)
      - load testing with fake players
      - **asleep while empty**: with no one in the hotel, its Lua stops altogether - Habbo's rooms
        only live while someone is in them - so an empty hotel uses next to no CPU. Every timer and
        tick (rooms, wired, pay, videos, effects) pauses; the server only listens for someone
        joining, then wakes up and picks up where it was. What has to happen while it's asleep is
        worked out on waking (club days ending, events finishing, timers that ran out), not by a
        clock. In Garry's Mod (which already hibernates an empty server) the hotel's own timers stop
        too; the desktop app's and the custom server's server sleep on the network
    - **Website**: the in-game one is done (the hotel's page after checking in, Lua, news from the
      website.news setting). Later, a web one for outside the game (a companion program next to a GMod
      server): front page, news, players online, Enter hotel, Steam / Discord login (no passwords), profiles
      (Habbo Home pages later), leaderboards, the staff page, an admin panel; themable
      - the owner can switch it off and use their own: an API (online, profiles, rooms, news, login
        tickets like Habbo's SSO) and "log in with your hotel" for other sites
      - safe from the start (forms, rate limits, the admin panel locked down); HTTPS behind the host's
        proxy
      - **WordPress plugin**: blocks (online, status, news, leaderboards, staff, profile cards, Enter
        hotel), log in with the hotel, hotel news from WordPress posts; thin (the API does the work),
        its key can only read and make login tickets
    - **Payments** (an addon, off by default): real money for credits, club and so on through a
      provider addon (e.g. Tebex, which handles VAT and refunds as the seller, or Stripe / PayPal).
      A content pack can say it shouldn't be sold for money: the Habbo pack does, and switching
      payments on with it warns the owner that a hotel selling Habbo's content may be taken down.
      Purchase logs, refunds and chargebacks, limits for young players.
    - **Discord**:
      - in the desktop app: Rich Presence (the hotel, the room or "hotel view", how long, how many),
        a Join button (a small web page that opens a `bobbahotel://` link the app registers, or a
        download link); players can switch it off or hide the room
      - a bot addon (bobba_discord): staff logs, the hotel's status in one message it keeps
        editing, chat of chosen rooms sent to Discord and Discord messages into the room (the
        word filter, mutes and bans apply to them; no pings out of the hotel); the token stays in the
        server's settings; Discord commands later
    - translations by the community (Danish, Spanish, Portuguese, Dutch, ...)
    - owner statistics: players over time, the economy

## Media (rooms, after the basics)

- **Radios**: internet radio stations (a public directory, by country and genre), heard nearby
  with distance like voice.
- **Videos**: started. Each room has a TV in the phone's Videos app (tablet): paste a YouTube link,
  a shared queue, half the room votes to skip, the owner skips, removes or turns it off; it plays in
  sync in GMod (the tablet, or a small player in the corner). Still to do for it:
- **TVs and cinema screens**: one shared media player (a link or search, a queue, skip votes, kept in
  sync; each player's game plays it itself). Services the owner allows (YouTube, Twitch, ...), room
  owners narrow it, staff block videos or channels, YouTube's restricted mode, a log of what was
  played. No free browser and no DRM services (Netflix etc. can't play in GMod's browser).
- **Jellyfin (and Plex) addon**: the host browses their library; a short-lived key per video, not
  their own; prefers files that play without converting.
- The desktop app needs its own video player for this (radio is easier); the web client gets it
  nearly free.

## Content and packs

- A furni creator: sprite sheets in, a furni pack out (sizes, directions, states, colours, sit height).
- Rooms as files and Workshop items: export a room (shape, look, furni) and import it anywhere; packs
  of rooms such as Habbo's public rooms decorated as they were.
- Starter rooms: packs register their own; the Habbo pack has the six classic coloured rooms.
- A Builders Club style build mode.
