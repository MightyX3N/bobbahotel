# Roadmap

What's done, what's next, and the ideas agreed for later, grouped under the part they belong to.
Nothing here is a promise of when; it keeps the plans in one place.

## Done

1. **The basics**: rooms drawn the way Nitro draws them, avatars, walking, chat, the toolbar, the
   catalogue, the inventory, wallet and club, gifts.
2. **Wall furni**: posters, stickies, mood lights, windows.
3. **Rooms** (mostly): the navigator, creating rooms, settings (access, rights, chat, moderation),
   the doorbell and passwords, kick / ban / mute, favourites and home rooms, the hotel view, the
   avatar menu and infostand, starter rooms (a new player picks one; packs register their own).
   Still open for rooms:
   - the floor plan editor
   - room thumbnails in the navigator (see the camera, part 4)
   - chat settings applied to the bubbles (mode, weight, speed, distance)
   - the navigator's "i" popover; report, word filter
   - a short tutorial after the starter room: walk, open the gift, place it, say hi (a small reward)

The desktop app (Love2D, runs the gamemode without GMod) is working: launcher, hosting a hotel,
borderless full screen, its own icon.

## Next

4. **Avatar**: the rest of the clothes editor, effects, dances, signs.
   - the camera: photos, photos as wall furni, room thumbnails for the navigator
   - walking with WASD, the arrow keys or a stick: continuous tile walking (holding a direction keeps
     stepping tile after tile, smoothly; diagonals with two keys; screen-relative by default, room
     axes as an option). Everything stays on tiles: sitting, rollers, wired and rooms keep working.
   - an interact button (E / A): the nearest usable thing (on your tile or next to you, the one
     you face first) is highlighted, and the button does what a double-click does: sit, lie down,
     switch, go through a teleport, open a gift, an avatar's menu; another button cycles between
     things equally close. The mouse keeps working alongside.
   - controller support (Steam Deck: GMod and the desktop app): walking as above, a cursor mode for
     furni, avatars and the UI, a radial menu for the toolbar, the on-screen keyboard or a
     quick-message wheel for chat, bumpers to turn furni and cycle selection
5. **Chat commands**.
6. **Friends and messenger**: friend requests, the messenger, following friends.
   - Steam friends who play the hotel are friends automatically; removing one removes them only in
     the hotel and puts them on a removed list so they aren't added again (unfriending is mutual);
     a note when a Steam friends list is private.
   - offline messages, "friend came online" notices
7. **Trading**, and the economy's safety:
   - every credit, purchase, trade and gift logged; limits on suspicious patterns (duplication,
     trade scams)
   - later: a marketplace like Habbo's
8. **Pets and bots**.
9. **Groups**.
10. **Rewards**: achievements, badges, daily quests, an advent calendar and seasonal events.
11. **Minigames and wired**.
    - games made for direct steering (WASD / stick): laser tag (shoot along the tile line you
      face, walls and furni block it, a hit stuns and scores, teams by colour), built from wired
      parts (a laser gun effect, a "hit by laser" trigger, team scores) so owners design their own
      arenas; the server decides hits. Banzai, Freeze and snowball fights play better this way too.
    - free movement (between tiles) only inside minigames that want it (a snowball fight, racing),
      never in the normal hotel
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
    - **Website (CMS)**, built in, on by default (a companion program next to a GMod server):
      front page, news, players online, Enter hotel, Steam / Discord login (no passwords), profiles
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
