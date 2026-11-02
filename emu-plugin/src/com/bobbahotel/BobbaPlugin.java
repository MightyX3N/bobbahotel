package com.bobbahotel;

import com.eu.habbo.Emulator;
import com.eu.habbo.habbohotel.bots.Bot;
import com.eu.habbo.habbohotel.commands.Command;
import com.eu.habbo.habbohotel.commands.CommandHandler;
import com.eu.habbo.habbohotel.gameclients.GameClient;
import com.eu.habbo.habbohotel.permissions.Permission;
import com.eu.habbo.habbohotel.rooms.Room;
import com.eu.habbo.habbohotel.rooms.RoomTile;
import com.eu.habbo.habbohotel.rooms.RoomUnit;
import com.eu.habbo.habbohotel.rooms.RoomUnitType;
import com.eu.habbo.habbohotel.rooms.RoomUserRotation;
import com.eu.habbo.habbohotel.users.Habbo;
import com.eu.habbo.habbohotel.users.HabboItem;
import com.eu.habbo.messages.outgoing.generic.alerts.BubbleAlertComposer;
import com.eu.habbo.messages.outgoing.rooms.ForwardToRoomComposer;
import com.eu.habbo.messages.outgoing.rooms.RoomThicknessComposer;
import com.eu.habbo.messages.outgoing.rooms.users.RoomUserStatusComposer;
import com.eu.habbo.messages.outgoing.rooms.users.RoomUsersComposer;
import com.eu.habbo.plugin.EventHandler;
import com.eu.habbo.plugin.EventListener;
import com.eu.habbo.plugin.HabboPlugin;
import com.eu.habbo.plugin.events.emulator.EmulatorLoadedEvent;
import com.eu.habbo.plugin.events.users.UserEnterRoomEvent;
import com.eu.habbo.plugin.events.users.UserExitRoomEvent;
import com.eu.habbo.plugin.events.users.UserTakeStepEvent;
import com.eu.habbo.threading.runnables.QueryDeleteHabboItem;
import gnu.trove.map.hash.THashMap;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Bobba Hotel's own additions to the game server.
 *
 * - There is no hotel view: everyone lands in the lobby (the room the owners picked on the admin
 *   pages, emulator_settings "bobba.lobby"). Walking out of a room through its door, being kicked
 *   or leaving takes you to the lobby; walking onto the lobby's own door does nothing.
 * - The lobby has a bot, Bobba. New players (with no room yet) get a welcome window with a
 *   "Get my room" button; clicking Bobba has the same button. It gives them a furnished room with a
 *   welcome gift (":getroom", sent by the client's button).
 * - Staff can delete a furni for good (":deletefurni <id>", sent by the client's Delete button).
 * - Rooms with hidden walls (outdoor rooms) really hide them: the server tells the client before the
 *   client has built the room, so it is told again once the room is there.
 */
public class BobbaPlugin extends HabboPlugin implements EventListener {
    static final String BOT_NAME = "Bobba";
    static final String HOTEL_LOOK = "hd-101.hr-101.ch-101.lg-101.sh-101";

    @Override
    public void onEnable() {
        Emulator.getPluginManager().registerEvents(this, this);
        CommandHandler.addCommand(new GetRoomCommand());
        CommandHandler.addCommand(new DeleteFurniCommand());
        if (Emulator.getRconServer() != null) onLoaded(null);
    }

    /** The RCON server exists only once the emulator has loaded. */
    @EventHandler
    public void onLoaded(EmulatorLoadedEvent event) {
        if (Emulator.getRconServer() != null) Emulator.getRconServer().addRCONMessage("bobbanavigator", UpdateNavigatorRcon.class);
    }

    @Override
    public void onDisable() {
    }

    @Override
    public boolean hasPermission(Habbo habbo, String key) {
        return false;
    }

    // ---- the lobby ----

    /** The lobby's room id (0 when none is picked yet). */
    static int lobby() {
        try (Connection c = Emulator.getDatabase().getDataSource().getConnection();
             PreparedStatement s = c.prepareStatement("SELECT `value` FROM emulator_settings WHERE `key` = 'bobba.lobby'");
             ResultSet r = s.executeQuery()) {
            if (r.next()) return Integer.parseInt(r.getString(1).trim());
        } catch (Exception e) {
            // no lobby
        }
        return 0;
    }

    static boolean ownsARoom(Habbo habbo) {
        try (Connection c = Emulator.getDatabase().getDataSource().getConnection();
             PreparedStatement s = c.prepareStatement("SELECT 1 FROM rooms WHERE owner_id = ? LIMIT 1")) {
            s.setInt(1, habbo.getHabboInfo().getId());
            try (ResultSet r = s.executeQuery()) {
                return r.next();
            }
        } catch (Exception e) {
            return true;
        }
    }

    /** Sends the player to the lobby, if there is one and they aren't in a room. */
    static void toLobby(Habbo habbo) {
        int lobby = lobby();
        if (lobby <= 0 || habbo.getClient() == null) return;
        habbo.getClient().sendResponse(new ForwardToRoomComposer(lobby));
    }

    @EventHandler
    public void onStep(UserTakeStepEvent event) {
        Habbo habbo = event.habbo;
        if (habbo == null || habbo.getRoomUnit() == null) return;
        Room room = habbo.getHabboInfo().getCurrentRoom();
        if (room == null || room.getLayout() == null) return;
        RoomTile door = room.getLayout().getDoorTile();
        if (door == null || event.toLocation != door || event.fromLocation == door) return;
        if (habbo.getRoomUnit().getGoal() != door) return;
        // Walking out of the lobby: there's nowhere to go, so you stay.
        if (room.getId() == lobby()) return;
        // Let the step onto the door be seen, then leave for the lobby.
        Emulator.getThreading().run(() -> {
            if (habbo.getHabboInfo().getCurrentRoom() == room && habbo.getRoomUnit().getCurrentLocation() == door) {
                Emulator.getGameEnvironment().getRoomManager().leaveRoom(habbo, room, false);
                toLobby(habbo);
            }
        }, 600);
    }

    /** Kicked, or left some other way: if they end up in no room, they go to the lobby. */
    @EventHandler
    public void onExit(UserExitRoomEvent event) {
        Habbo habbo = event.habbo;
        if (habbo == null) return;
        Emulator.getThreading().run(() -> {
            if (habbo.isOnline() && habbo.getHabboInfo().getCurrentRoom() == null && habbo.getHabboInfo().getLoadingRoom() == 0) toLobby(habbo);
        }, 800);
    }

    @EventHandler
    public void onEnter(UserEnterRoomEvent event) {
        Room room = event.room;
        Habbo habbo = event.habbo;
        if (room == null || habbo == null) return;
        if (room.isHideWall()) {
            for (int delay : new int[]{1500, 4000}) {
                Emulator.getThreading().run(() -> {
                    if (habbo.getClient() != null && habbo.getHabboInfo().getCurrentRoom() == room) {
                        habbo.getClient().sendResponse(new RoomThicknessComposer(room));
                    }
                }, delay);
            }
        }
        if (room.getId() == lobby()) {
            Emulator.getThreading().run(() -> {
                ensureBot(room);
                if (habbo.getClient() != null && habbo.getHabboInfo().getCurrentRoom() == room && !ownsARoom(habbo)) welcome(habbo);
            }, 2500);
        }
    }

    /** The welcome window (Nitro shows it as an alert with a button that opens our link). */
    static void welcome(Habbo habbo) {
        THashMap<String, String> keys = new THashMap<>();
        keys.put("title", "Welcome to Bobba Hotel!");
        keys.put("message", "Hi " + habbo.getHabboInfo().getUsername() + ", I'm Bobba. Would you like a room of your own? You get it furnished, with a welcome gift inside.");
        keys.put("linkTitle", "Get my room");
        keys.put("linkUrl", "bobba/getroom");
        keys.put("image", "");
        habbo.getClient().sendResponse(new BubbleAlertComposer("bobba.welcome", keys));
    }

    /** Puts Bobba the bot in the lobby (next to the door) if it isn't there. */
    static synchronized void ensureBot(Room room) {
        for (Bot b : room.getCurrentBots().valueCollection()) if (BOT_NAME.equals(b.getName())) return;
        RoomTile door = room.getLayout().getDoorTile();
        RoomTile spot = null;
        if (door != null) {
            int[][] around = {{1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {2, 0}};
            for (int[] d : around) {
                RoomTile t = room.getLayout().getTile((short) (door.x + d[0]), (short) (door.y + d[1]));
                if (t != null && t.isWalkable() && !room.hasHabbosAt(t.x, t.y) && !room.hasBotsAt(t.x, t.y) && room.getTopItemAt(t.x, t.y) == null) { spot = t; break; }
            }
        }
        if (spot == null) return;
        THashMap<String, String> data = new THashMap<>();
        data.put("name", BOT_NAME);
        data.put("motto", "Click me for a room of your own!");
        data.put("figure", HOTEL_LOOK);
        data.put("gender", "M");
        Bot bot = Emulator.getGameEnvironment().getBotManager().createBot(data, "generic");
        if (bot == null) return;
        try (Connection c = Emulator.getDatabase().getDataSource().getConnection();
             PreparedStatement s = c.prepareStatement("UPDATE bots SET user_id = 1 WHERE id = ?")) {
            s.setInt(1, bot.getId());
            s.execute();
        } catch (Exception e) {
            // it still works, only its owner shows as nobody
        }
        RoomUnit unit = new RoomUnit();
        unit.setRotation(RoomUserRotation.SOUTH_EAST);
        unit.setLocation(spot);
        unit.setPreviousLocationZ(spot.getStackHeight());
        unit.setZ(spot.getStackHeight());
        unit.setPathFinderRoom(room);
        unit.setRoomUnitType(RoomUnitType.BOT);
        unit.setCanWalk(false);
        bot.setRoomUnit(unit);
        bot.setRoom(room);
        bot.needsUpdate(true);
        room.addBot(bot);
        Emulator.getThreading().run(bot);
        room.sendComposer(new RoomUsersComposer(bot).compose());
        room.sendComposer(new RoomUserStatusComposer(bot.getRoomUnit()).compose());
    }

    // ---- first rooms ----

    /** A new player's room: Habbo's small starter layout (model_c), some furni, a welcome gift. */
    static final String MODEL = "model_c";
    static final Object[][] FURNI = {
        {"bobba_bed_g_4", 9, 5, 0, ""},
        {"bobba_plant_2", 5, 5, 0, ""},
        {"bobba_sofa_1", 6, 5, 4, ""},
        {"bobba_lamp_10", 7, 5, 0, ""},
        {"bobba_carpet_14", 6, 7, 0, ""},
        {"bobba_smalltable_5", 6, 7, 2, ""},
        {"bobba_window_8", 0, 0, 0, ":w=6,4 l=10,34 r"},
    };
    static final String[] GIFT_CONTENTS = {"bobba_lava_lamp", "bobba_plant_3", "bobba_picture_modern_1"};
    static final String GIFT_MESSAGE = "Welcome to Bobba Hotel! Here is something for your new room.";

    static int createStarterRoom(Habbo habbo) throws Exception {
        int userId = habbo.getHabboInfo().getId();
        String name = habbo.getHabboInfo().getUsername();
        try (Connection c = Emulator.getDatabase().getDataSource().getConnection()) {
            int roomId;
            try (PreparedStatement s = c.prepareStatement(
                "INSERT INTO rooms (owner_id, owner_name, name, description, model, state, users_max, paper_floor, paper_wall, paper_landscape, thickness_wall, wall_height, thickness_floor, moodlight_data, tags, is_public, category) " +
                "VALUES (?, ?, ?, '', ?, 'open', 25, '0.0', '0.0', '0.0', 0, -1, 0, '', '', '0', 1)", Statement.RETURN_GENERATED_KEYS)) {
                s.setInt(1, userId);
                s.setString(2, name);
                s.setString(3, name + "'s room");
                s.setString(4, MODEL);
                s.execute();
                try (ResultSet r = s.getGeneratedKeys()) {
                    r.next();
                    roomId = r.getInt(1);
                }
            }
            Map<String, Integer> ids = new LinkedHashMap<>();
            try (PreparedStatement s = c.prepareStatement("SELECT id, item_name FROM items_base WHERE item_name LIKE 'bobba\\_%'");
                 ResultSet r = s.executeQuery()) {
                while (r.next()) ids.put(r.getString(2), r.getInt(1));
            }
            try (PreparedStatement s = c.prepareStatement("INSERT INTO items (user_id, room_id, item_id, wall_pos, x, y, z, rot, extra_data) VALUES (?, ?, ?, ?, ?, ?, 0, ?, '0')")) {
                for (Object[] f : FURNI) {
                    Integer base = ids.get((String) f[0]);
                    if (base == null) continue;
                    s.setInt(1, userId);
                    s.setInt(2, roomId);
                    s.setInt(3, base);
                    s.setString(4, (String) f[4]);
                    s.setInt(5, (Integer) f[1]);
                    s.setInt(6, (Integer) f[2]);
                    s.setInt(7, (Integer) f[3]);
                    s.execute();
                }
            }
            // The gift: its furni belong to nobody until it's opened (as Arcturus keeps gifts).
            List<Integer> inside = new ArrayList<>();
            try (PreparedStatement s = c.prepareStatement("INSERT INTO items (user_id, room_id, item_id, wall_pos, x, y, z, rot, extra_data) VALUES (0, 0, ?, '', 0, 0, 0, 0, '0')", Statement.RETURN_GENERATED_KEYS)) {
                for (String f : GIFT_CONTENTS) {
                    Integer base = ids.get(f);
                    if (base == null) continue;
                    s.setInt(1, base);
                    s.execute();
                    try (ResultSet r = s.getGeneratedKeys()) {
                        if (r.next()) inside.add(r.getInt(1));
                    }
                }
            }
            Integer gift = ids.get("bobba_gift");
            if (gift != null && !inside.isEmpty()) {
                StringBuilder data = new StringBuilder().append(inside.size());
                for (int id : inside) data.append('\t').append(id);
                data.append("\t0\t0\t1\t").append(GIFT_MESSAGE).append("\tBobba\t").append(HOTEL_LOOK);
                try (PreparedStatement s = c.prepareStatement("INSERT INTO items (user_id, room_id, item_id, wall_pos, x, y, z, rot, extra_data) VALUES (?, ?, ?, '', 8, 8, 0, 0, ?)")) {
                    s.setInt(1, userId);
                    s.setInt(2, roomId);
                    s.setInt(3, gift);
                    s.setString(4, data.toString());
                    s.execute();
                }
            }
            return roomId;
        }
    }

    /** ":getroom" (the "Get my room" button): a first room, once. */
    static class GetRoomCommand extends Command {
        GetRoomCommand() {
            super(null, new String[]{"getroom"});
        }

        @Override
        public boolean handle(GameClient client, String[] params) throws Exception {
            Habbo habbo = client.getHabbo();
            if (habbo == null) return true;
            if (ownsARoom(habbo)) {
                habbo.whisper("You already have a room: find it in the navigator under My rooms.");
                return true;
            }
            int roomId = createStarterRoom(habbo);
            Emulator.getGameEnvironment().getRoomManager().loadRoomsForHabbo(habbo);
            client.sendResponse(new ForwardToRoomComposer(roomId));
            return true;
        }
    }

    /** ":deletefurni <id>" (staff, the Delete button): the furni is gone, not into an inventory. */
    static class DeleteFurniCommand extends Command {
        DeleteFurniCommand() {
            super(null, new String[]{"deletefurni"});
        }

        @Override
        public boolean handle(GameClient client, String[] params) throws Exception {
            Habbo habbo = client.getHabbo();
            if (habbo == null || !habbo.hasPermission(Permission.ACC_ANYROOMOWNER)) return true;
            Room room = habbo.getHabboInfo().getCurrentRoom();
            if (room == null || params.length < 2) return true;
            int id;
            try {
                id = Integer.parseInt(params[1]);
            } catch (NumberFormatException e) {
                return true;
            }
            HabboItem item = room.getHabboItem(id);
            if (item == null) return true;
            room.pickUpItem(item, null);
            item.setUserId(0);
            Emulator.getThreading().run(new QueryDeleteHabboItem(item.getId()));
            return true;
        }
    }
}
