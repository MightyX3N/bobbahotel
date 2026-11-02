package com.bobbahotel;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Rooms at TinyHouse scale: every tile of a Habbo layout becomes 2x2 smaller tiles (the room keeps
 * its shape and its size on screen; the TinyHouse furni fit in it). Done once, at start-up, before
 * the emulator loads any layout or room (emulator_settings bobba.tinyscale = 1 afterwards):
 *
 *   - layouts (room_models, room_models_custom): each tile 2x2, heights doubled too (a step stays as
 *     tall next to the avatar); the door stays one tile sticking out of the wall
 *   - furni, bots and pets: positions and heights doubled, so everything keeps its place
 *   - rooms with a fixed wall height: doubled
 *
 * Layouts named model_tiny* are made at the new scale already and are left alone.
 */
final class TinyScale {
    private TinyScale() {
    }

    static void run(Connection c) throws SQLException {
        if ("1".equals(setting(c))) return;
        c.setAutoCommit(false);
        try {
            int models = layouts(c, "SELECT name, door_x, door_y, heightmap FROM room_models WHERE name NOT LIKE 'model_tiny%'",
                    "UPDATE room_models SET door_x = ?, door_y = ?, heightmap = ? WHERE name = ?");
            int custom = layouts(c, "SELECT id, door_x, door_y, heightmap FROM room_models_custom",
                    "UPDATE room_models_custom SET door_x = ?, door_y = ?, heightmap = ? WHERE id = ?");
            try (Statement s = c.createStatement()) {
                s.executeUpdate("UPDATE items SET x = x * 2, y = y * 2, z = z * 2 WHERE wall_pos = '' OR wall_pos IS NULL");
                s.executeUpdate("UPDATE bots SET x = x * 2, y = y * 2, z = z * 2");
                s.executeUpdate("UPDATE users_pets SET x = x * 2, y = y * 2, z = z * 2");
                s.executeUpdate("UPDATE rooms SET wall_height = wall_height * 2 WHERE wall_height > 0");
            }
            int wall = wallItems(c);
            try (PreparedStatement p = c.prepareStatement("INSERT INTO emulator_settings (`key`, `value`) VALUES ('bobba.tinyscale', '1') ON DUPLICATE KEY UPDATE `value` = '1'")) {
                p.executeUpdate();
            }
            c.commit();
            System.out.println("[Bobba] Rooms at TinyHouse scale: " + models + " layouts, " + custom + " custom layouts, " + wall + " wall furni converted.");
        } catch (SQLException e) {
            c.rollback();
            throw e;
        } finally {
            c.setAutoCommit(true);
        }
    }

    private static String setting(Connection c) throws SQLException {
        try (PreparedStatement p = c.prepareStatement("SELECT `value` FROM emulator_settings WHERE `key` = 'bobba.tinyscale'");
             ResultSet r = p.executeQuery()) {
            return r.next() ? r.getString(1) : null;
        }
    }

    private static int layouts(Connection c, String select, String update) throws SQLException {
        List<Object[]> rows = new ArrayList<>();
        try (Statement s = c.createStatement(); ResultSet r = s.executeQuery(select)) {
            while (r.next()) rows.add(new Object[]{r.getObject(1), r.getInt(2), r.getInt(3), r.getString(4)});
        }
        try (PreparedStatement p = c.prepareStatement(update)) {
            for (Object[] row : rows) {
                Layout l = doubled((String) row[3], (int) row[1], (int) row[2]);
                p.setInt(1, l.doorX);
                p.setInt(2, l.doorY);
                p.setString(3, l.heightmap);
                p.setObject(4, row[0]);
                p.addBatch();
            }
            p.executeBatch();
        }
        return rows.size();
    }

    static final class Layout {
        final String heightmap;
        final int doorX, doorY;

        Layout(String heightmap, int doorX, int doorY) {
            this.heightmap = heightmap;
            this.doorX = doorX;
            this.doorY = doorY;
        }
    }

    /** A height character twice as high ('x' stays void). Heights are 0-9 then a, b, c, ... */
    static char higher(char ch) {
        if (ch == 'x' || ch == 'X') return 'x';
        int h = Character.isDigit(ch) ? ch - '0' : 10 + (Character.toLowerCase(ch) - 'a');
        int d = Math.min(h * 2, 32);
        return d < 10 ? (char) ('0' + d) : (char) ('a' + d - 10);
    }

    /** Every tile 2x2 and twice as high; the door one tile sticking out of the wall, as before. */
    static Layout doubled(String heightmap, int doorX, int doorY) {
        String[] rows = heightmap.replace("\r\n", "\r").replace("\n", "\r").split("\r");
        int h = rows.length, w = 0;
        for (String row : rows) w = Math.max(w, row.length());
        char[][] old = new char[h][w];
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) old[y][x] = x < rows[y].length() ? rows[y].charAt(x) : 'x';
        char[][] map = new char[h * 2][w * 2];
        for (int y = 0; y < h * 2; y++) for (int x = 0; x < w * 2; x++) map[y][x] = higher(old[y / 2][x / 2]);

        // The door: of its 2x2 tiles keep the one next to the room, the others become void.
        int dx = 2 * doorX, dy = 2 * doorY;
        if (doorX >= 0 && doorY >= 0 && doorY < h && doorX < w && old[doorY][doorX] != 'x') {
            int[][] sides = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
            int[] in = null;
            for (int[] s : sides) {
                int nx = doorX + s[0], ny = doorY + s[1];
                if (nx >= 0 && ny >= 0 && nx < w && ny < h && old[ny][nx] != 'x') { in = s; break; }
            }
            if (in != null) {
                int keepX = 2 * doorX + (in[0] > 0 ? 1 : 0), keepY = 2 * doorY + (in[1] > 0 ? 1 : 0);
                for (int y = 2 * doorY; y < 2 * doorY + 2; y++)
                    for (int x = 2 * doorX; x < 2 * doorX + 2; x++)
                        if (x != keepX || y != keepY) map[y][x] = 'x';
                dx = keepX;
                dy = keepY;
            }
        }
        StringBuilder out = new StringBuilder();
        for (int y = 0; y < h * 2; y++) {
            if (y > 0) out.append("\r\n");
            out.append(map[y]);
        }
        return new Layout(out.toString(), dx, dy);
    }

    private static final Pattern WALL = Pattern.compile(":w=(-?\\d+),(-?\\d+) l=(-?\\d+),(-?\\d+) ([lr])");

    /** Wall furni (":w=6,4 l=10,34 r"): the wall tile and the offset on it, both doubled. */
    private static int wallItems(Connection c) throws SQLException {
        List<Object[]> rows = new ArrayList<>();
        try (Statement s = c.createStatement(); ResultSet r = s.executeQuery("SELECT id, wall_pos FROM items WHERE wall_pos LIKE ':w=%'")) {
            while (r.next()) rows.add(new Object[]{r.getInt(1), r.getString(2)});
        }
        try (PreparedStatement p = c.prepareStatement("UPDATE items SET wall_pos = ? WHERE id = ?")) {
            for (Object[] row : rows) {
                Matcher m = WALL.matcher((String) row[1]);
                if (!m.find()) continue;
                p.setString(1, ":w=" + 2 * Integer.parseInt(m.group(1)) + "," + 2 * Integer.parseInt(m.group(2))
                        + " l=" + 2 * Integer.parseInt(m.group(3)) + "," + 2 * Integer.parseInt(m.group(4)) + " " + m.group(5));
                p.setInt(2, (int) row[0]);
                p.addBatch();
            }
            p.executeBatch();
        }
        return rows.size();
    }
}
