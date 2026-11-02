package com.bobbahotel;

import com.eu.habbo.Emulator;
import com.eu.habbo.habbohotel.rooms.Room;
import com.eu.habbo.habbohotel.rooms.RoomTile;
import com.eu.habbo.habbohotel.users.Habbo;
import com.eu.habbo.plugin.EventHandler;
import com.eu.habbo.plugin.EventListener;
import com.eu.habbo.plugin.HabboPlugin;
import com.eu.habbo.messages.outgoing.rooms.RoomThicknessComposer;
import com.eu.habbo.plugin.events.users.UserEnterRoomEvent;
import com.eu.habbo.plugin.events.users.UserTakeStepEvent;

/**
 * Bobba Hotel's own additions to the game server.
 *
 * - Leaving a room through its door, the way Habbo does it: whoever walks onto the door tile (on
 *   purpose: it's where they were walking to) leaves the room and goes to the hotel view.
 * - Rooms with hidden walls (outdoor rooms) really hide them: the server tells the client before the
 *   client has built the room, so it is told again once the room is there.
 */
public class BobbaPlugin extends HabboPlugin implements EventListener {
    @Override
    public void onEnable() {
        Emulator.getPluginManager().registerEvents(this, this);
    }

    @Override
    public void onDisable() {
    }

    @Override
    public boolean hasPermission(Habbo habbo, String key) {
        return false;
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
        // Let the step onto the door be seen, then leave.
        Emulator.getThreading().run(() -> {
            if (habbo.getHabboInfo().getCurrentRoom() == room && habbo.getRoomUnit().getCurrentLocation() == door) {
                Emulator.getGameEnvironment().getRoomManager().leaveRoom(habbo, room);
            }
        }, 600);
    }

    @EventHandler
    public void onEnter(UserEnterRoomEvent event) {
        Room room = event.room;
        Habbo habbo = event.habbo;
        if (room == null || habbo == null || !room.isHideWall()) return;
        for (int delay : new int[]{1500, 4000}) {
            Emulator.getThreading().run(() -> {
                if (habbo.getClient() != null && habbo.getHabboInfo().getCurrentRoom() == room) {
                    habbo.getClient().sendResponse(new RoomThicknessComposer(room));
                }
            }, delay);
        }
    }
}
