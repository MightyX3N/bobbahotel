// Arcturus's pathfinder (RoomLayout / RoomTile, github.com/ArcturusEmulator, GPL-3), the methods copied
// unchanged (RoomTile without its item and unit-set classes); only the server around them (room,
// config, units) is replaced. Reads cases on stdin, prints the paths.
import java.util.*;
import java.io.*;

enum RoomTileState { OPEN, BLOCKED, INVALID, SIT, LAY }

class RoomUnit { boolean canOverrideTile(RoomTile t) { return false; } }

class Emulator {
    static boolean isNumeric(String s) { try { Short.parseShort(s); return true; } catch (Exception e) { return false; } }
    static Config getConfig() { return new Config(); }
}
class Config { int getInt(String k, int d) { return d; } boolean getBoolean(String k, boolean d) { return d; } }

class Room {
    RoomLayout layout; boolean walkthrough;
    boolean isLoaded() { return true; }
    RoomLayout getLayout() { return this.layout; }
    boolean isAllowWalkthrough() { return this.walkthrough; }
}







class RoomTile {
    public final short x;
    public final short y;
    public final short z;
    final int[] units;
    public RoomTileState state;
    private double stackHeight;
    private boolean allowStack = true;
    private RoomTile previous = null;
    private boolean diagonally;
    private short gCosts;
    private short hCosts;


    public RoomTile(short x, short y, short z, RoomTileState state, boolean allowStack) {
        this.x = x;
        this.y = y;
        this.z = z;
        this.stackHeight = z;
        this.state = state;
        this.setAllowStack(allowStack);
        this.units = new int[1];
    }

    public RoomTile(RoomTile tile) {
        this.x = tile.x;
        this.y = tile.y;
        this.z = tile.z;
        this.stackHeight = tile.stackHeight;
        this.state = tile.state;
        this.allowStack = tile.allowStack;
        this.diagonally = tile.diagonally;
        this.gCosts = tile.gCosts;
        this.hCosts = tile.hCosts;

        if (this.state == RoomTileState.INVALID) {
            this.allowStack = false;
        }
        this.units = tile.units;
    }

    public RoomTile()
    {
        x = 0;
        y = 0;
        z = 0;
        this.stackHeight = 0;
        this.state = RoomTileState.INVALID;
        this.allowStack = false;
        this.diagonally = false;
        this.gCosts = 0;
        this.hCosts = 0;
        this.units = new int[1];
    }

    public double getStackHeight() {
        return this.stackHeight;
    }

    public void setStackHeight(double stackHeight) {
        if (this.state == RoomTileState.INVALID) {
            this.stackHeight = Short.MAX_VALUE;
            this.allowStack = false;
            return;
        }

        if (stackHeight >= 0 && stackHeight != Short.MAX_VALUE) {
            this.stackHeight = stackHeight;
            this.allowStack = true;
        } else {
            this.allowStack = false;
            this.stackHeight = this.z;
        }
    }

    public boolean getAllowStack() {
        if (this.state == RoomTileState.INVALID) {
            return false;
        }

        return this.allowStack;
    }

    public void setAllowStack(boolean allowStack) {
        this.allowStack = allowStack;
    }

    public short relativeHeight() {
        if (this.state == RoomTileState.INVALID) {
            return Short.MAX_VALUE;
        } else if (!this.allowStack && (this.state == RoomTileState.BLOCKED || this.state == RoomTileState.SIT)) {
            return 64 * 256;
        }

        return this.allowStack ? (short) (this.getStackHeight() * 256.0) : 64 * 256;
    }

    @Override
    public boolean equals(Object o) {
        return o instanceof RoomTile &&
                ((RoomTile) o).x == this.x &&
                ((RoomTile) o).y == this.y;
    }

    public RoomTile copy() {
        return new RoomTile(this);
    }

    public double distance(RoomTile roomTile) {
        double x = this.x - roomTile.x;
        double y = this.y - roomTile.y;
        return Math.sqrt(x * x + y * y);
    }

    public void isDiagonally(boolean isDiagonally) {
        this.diagonally = isDiagonally;
    }

    public RoomTile getPrevious() {
        return this.previous;
    }

    public void setPrevious(RoomTile previous) {
        this.previous = previous;
    }

    public int getfCosts() {
        return this.gCosts + this.hCosts;
    }

    public int getgCosts() {
        return this.gCosts;
    }

    public void setgCosts(RoomTile previousRoomTile) {
        this.setgCosts(previousRoomTile, this.diagonally ? RoomLayout.DIAGONALMOVEMENTCOST : RoomLayout.BASICMOVEMENTCOST);
    }

    private void setgCosts(short gCosts) {
        this.gCosts = gCosts;
    }

    void setgCosts(RoomTile previousRoomTile, int basicCost) {
        this.setgCosts((short) (previousRoomTile.getgCosts() + basicCost));
    }

    public int calculategCosts(RoomTile previousRoomTile) {
        if (this.diagonally) {
            return previousRoomTile.getgCosts() + 14;
        }

        return previousRoomTile.getgCosts() + 10;
    }

    public void sethCosts(RoomTile parent) {
        this.hCosts = (short) ((Math.abs(this.x - parent.x) + Math.abs(this.y - parent.y)) * (parent.diagonally ? RoomLayout.DIAGONALMOVEMENTCOST : RoomLayout.BASICMOVEMENTCOST));
    }

    public String toString() {
        return "RoomTile (" + this.x + ", " + this.y + ", " + this.z + "): h: " + this.hCosts + " g: " + this.gCosts + " f: " + this.getfCosts();
    }

    public boolean isWalkable() {
        return this.state == RoomTileState.OPEN;
    }

    public RoomTileState getState() {
        return this.state;
    }

    public void setState(RoomTileState state) {
        this.state = state;
    }

    public boolean is(short x, short y) {
        return this.x == x && this.y == y;
    }

    public boolean hasUnits() { return this.units[0] > 0; }

    }


class RoomLayout {
    protected static final int BASICMOVEMENTCOST = 10;
    protected static final int DIAGONALMOVEMENTCOST = 14;
    public static double MAXIMUM_STEP_HEIGHT = 1.1;
    public static boolean ALLOW_FALLING = true;
    public boolean CANMOVEDIAGONALY = true;
    private short doorX, doorY, doorZ;
    private int doorDirection;
    private String heightmap;
    private int mapSizeX, mapSizeY, mapSize;
    private RoomTile[][] roomTiles;
    private RoomTile doorTile;
    private Room room;

    RoomLayout(String heightmap, short doorX, short doorY, int doorDirection, Room room) {
        this.heightmap = heightmap; this.doorX = doorX; this.doorY = doorY; this.doorDirection = doorDirection; this.room = room;
        this.parse();
    }
    public int getMapSizeX() { return this.mapSizeX; }
    public int getMapSizeY() { return this.mapSizeY; }
    public RoomTile getDoorTile() { return this.doorTile; }

    public void parse() {
        String[] modelTemp = this.heightmap.replace("\n", "").split(Character.toString('\r'));

        this.mapSize = 0;
        this.mapSizeX = modelTemp[0].length();
        this.mapSizeY = modelTemp.length;
        this.roomTiles = new RoomTile[this.mapSizeX][this.mapSizeY];

        for (short y = 0; y < this.mapSizeY; y++) {
            if (modelTemp[y].isEmpty() || modelTemp[y].equalsIgnoreCase("\r")) {
                continue;
            }

            for (short x = 0; x < this.mapSizeX; x++) {
                if (modelTemp[y].length() != this.mapSizeX) {
                    break;
                }

                String square = modelTemp[y].substring(x, x + 1).trim().toLowerCase();
                RoomTileState state = RoomTileState.OPEN;
                short height = 0;
                if (square.equalsIgnoreCase("x")) {
                    state = RoomTileState.INVALID;
                } else {
                    if (square.isEmpty()) {
                        height = 0;
                    } else if (Emulator.isNumeric(square)) {
                        height = Short.parseShort(square);
                    } else {
                        height = (short) (10 + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".indexOf(square.toUpperCase()));
                    }
                }
                this.mapSize += 1;

                this.roomTiles[x][y] = new RoomTile(x, y, height, state, true);
            }
        }

        this.doorTile = this.roomTiles[this.doorX][this.doorY];

        if (this.doorTile != null) {
            this.doorTile.setAllowStack(false);
            RoomTile doorFrontTile = this.getTileInFront(this.doorTile, this.doorDirection);

            if (doorFrontTile != null && this.tileExists(doorFrontTile.x, doorFrontTile.y)) {
                if (this.roomTiles[doorFrontTile.x][doorFrontTile.y].state != RoomTileState.INVALID) {
                    if (this.doorZ != this.roomTiles[doorFrontTile.x][doorFrontTile.y].z || this.roomTiles[this.doorX][this.doorY].state != this.roomTiles[doorFrontTile.x][doorFrontTile.y].state) {
                        this.doorZ = this.roomTiles[doorFrontTile.x][doorFrontTile.y].z;
                        this.roomTiles[this.doorX][this.doorY].state = RoomTileState.OPEN;
                    }
                }
            }
        }
    }

    public RoomTile getTile(short x, short y) {
        if (this.tileExists(x, y)) {
            return this.roomTiles[x][y];
        }

        return null;
    }

    public boolean tileExists(short x, short y) {
        return !(x < 0 || y < 0 || x >= this.getMapSizeX() || y >= this.getMapSizeY());
    }

    public RoomTile getTileInFront(RoomTile tile, int rotation) { return this.getTileInFront(tile, rotation, 0); }

    public RoomTile getTileInFront(RoomTile tile, int rotation, int offset) {
        int offsetX = 0;
        int offsetY = 0;

        rotation = rotation % 8;
        switch (rotation) {
            case 0:
                offsetY--;
                break;
            case 1:
                offsetX++;
                offsetY--;
                break;
            case 2:
                offsetX++;
                break;
            case 3:
                offsetX++;
                offsetY++;
                break;
            case 4:
                offsetY++;
                break;
            case 5:
                offsetX--;
                offsetY++;
                break;
            case 6:
                offsetX--;
                break;
            case 7:
                offsetX--;
                offsetY--;
                break;
        }

        short x = tile.x;
        short y = tile.y;

        for (int i = 0; i <= offset; i++) {
            x += offsetX;
            y += offsetY;
        }

        return this.getTile(x, y);
    }

    public final Deque<RoomTile> findPath(RoomTile oldTile, RoomTile newTile, RoomTile goalLocation, RoomUnit roomUnit, boolean isWalktroughRetry) {
        if (this.room == null || !this.room.isLoaded() || oldTile == null || newTile == null || oldTile.equals(newTile) || newTile.state == RoomTileState.INVALID)
            return new LinkedList<>();

        LinkedList<RoomTile> openList = new LinkedList<>();
        List<RoomTile> closedList = new LinkedList<>();
        openList.add(oldTile.copy());

        RoomTile doorTile = this.room.getLayout().getDoorTile();

        long startMillis = System.currentTimeMillis();

        while (!openList.isEmpty()) {
            if (System.currentTimeMillis() - startMillis > Emulator.getConfig().getInt("pathfinder.execution_time.milli", 25) && Emulator.getConfig().getBoolean("pathfinder.max_execution_time.enabled", false)) {
                return null;
            }

            RoomTile current = this.lowestFInOpen(openList);
            if (current.x == newTile.x && current.y == newTile.y) {
                return this.calcPath(this.findTile(openList, oldTile.x, oldTile.y), current);
            }

            closedList.add(current);
            openList.remove(current);

            List<RoomTile> adjacentNodes = this.getAdjacent(openList, current, newTile, roomUnit);
            for (RoomTile currentAdj : adjacentNodes) {
                if (closedList.contains(currentAdj)) continue;

                if (roomUnit.canOverrideTile(currentAdj)) {
                    currentAdj.setPrevious(current);
                    currentAdj.sethCosts(this.findTile(openList, newTile.x, newTile.y));
                    currentAdj.setgCosts(current);
                    openList.add(currentAdj);
                    continue;
                }

                if (currentAdj.state == RoomTileState.BLOCKED || ((currentAdj.state == RoomTileState.SIT || currentAdj.state == RoomTileState.LAY) && !currentAdj.equals(goalLocation))) {
                    closedList.add(currentAdj);
                    openList.remove(currentAdj);
                    continue;
                }

                double height = currentAdj.getStackHeight() - current.getStackHeight();

                if ((!ALLOW_FALLING && height < -MAXIMUM_STEP_HEIGHT) || (currentAdj.state == RoomTileState.OPEN && height > MAXIMUM_STEP_HEIGHT)) {
                    closedList.add(currentAdj);
                    openList.remove(currentAdj);
                    continue;
                }

                if (currentAdj.hasUnits() && doorTile.distance(currentAdj) > 2 && (!isWalktroughRetry || !this.room.isAllowWalkthrough() || currentAdj.equals(goalLocation))) {
                    closedList.add(currentAdj);
                    openList.remove(currentAdj);
                    continue;
                }

                if (!openList.contains(currentAdj)) {
                    currentAdj.setPrevious(current);
                    currentAdj.sethCosts(this.findTile(openList, newTile.x, newTile.y));
                    currentAdj.setgCosts(current);
                    openList.add(currentAdj);
                } else if (currentAdj.getgCosts() > currentAdj.calculategCosts(current)) {
                    currentAdj.setPrevious(current);
                    currentAdj.setgCosts(current);
                }
            }
        }

        if (this.room.isAllowWalkthrough() && !isWalktroughRetry) {
            return this.findPath(oldTile, newTile, goalLocation, roomUnit, true);
        }

        return null;
    }

    private RoomTile findTile(List<RoomTile> tiles, short x, short y) {
        for (RoomTile tile : tiles) {
            if (x == tile.x && y == tile.y) {
                return tile;
            }
        }

        RoomTile tile = this.getTile(x, y);

        if (tile != null) {
            return tile.copy();
        }
        return null;
    }

    public Deque<RoomTile> calcPath(RoomTile start, RoomTile goal) {
        LinkedList<RoomTile> path = new LinkedList<>();
        if (start == null)
            return path;

        RoomTile curr = goal;
        while (curr != null) {
            path.addFirst(this.getTile(curr.x, curr.y));
            curr = curr.getPrevious();
            if ((curr != null) && (curr.equals(start))) {
                return path;
            }
        }
        return path;
    }

    private RoomTile lowestFInOpen(List<RoomTile> openList) {
        if (openList == null)
            return null;

        RoomTile cheapest = openList.get(0);
        for (RoomTile anOpenList : openList) {
            if (anOpenList.getfCosts() < cheapest.getfCosts()) {
                cheapest = anOpenList;
            }
        }
        return cheapest;
    }

    private List<RoomTile> getAdjacent(List<RoomTile> openList, RoomTile node, RoomTile nextTile, RoomUnit unit) {
        short x = node.x;
        short y = node.y;
        List<RoomTile> adj = new LinkedList<>();
        if (x > 0) {
            RoomTile temp = this.findTile(openList, (short) (x - 1), y);
            if (this.canWalkOn(temp, unit)) {
                if (temp.state != RoomTileState.SIT || nextTile.getStackHeight() - node.getStackHeight() <= 2.0) {
                    temp.isDiagonally(false);
                    if (!adj.contains(temp))
                        adj.add(temp);
                }
            }
        }
        if (x < this.mapSizeX) {
            RoomTile temp = this.findTile(openList, (short) (x + 1), y);
            if (this.canWalkOn(temp, unit)) {
                if (temp.state != RoomTileState.SIT || nextTile.getStackHeight() - node.getStackHeight() <= 2.0) {
                    temp.isDiagonally(false);
                    if (!adj.contains(temp))
                        adj.add(temp);
                }
            }
        }
        if (y > 0) {
            RoomTile temp = this.findTile(openList, x, (short) (y - 1));
            if (this.canWalkOn(temp, unit)) {
                if (temp.state != RoomTileState.SIT || nextTile.getStackHeight() - node.getStackHeight() <= 2.0) {
                    temp.isDiagonally(false);
                    if (!adj.contains(temp))
                        adj.add(temp);
                }
            }
        }
        if (y < this.mapSizeY) {
            RoomTile temp = this.findTile(openList, x, (short) (y + 1));
            if (this.canWalkOn(temp, unit)) {
                if (temp.state != RoomTileState.SIT || nextTile.getStackHeight() - node.getStackHeight() <= 2.0) {
                    temp.isDiagonally(false);
                    if (!adj.contains(temp))
                        adj.add(temp);
                }
            }
        }
        if (this.CANMOVEDIAGONALY) {
            if ((x < this.mapSizeX) && (y < this.mapSizeY)) {
                RoomTile offX = this.findTile(openList, (short) (x + 1), y);
                RoomTile offY = this.findTile(openList, x, (short) (y + 1));
                if (offX != null && offY != null && (offX.isWalkable() || offY.isWalkable())) {
                    RoomTile temp = this.findTile(openList, (short) (x + 1), (short) (y + 1));
                    if (this.canWalkOn(temp, unit)) {
                        if (temp.state != RoomTileState.SIT || nextTile.getStackHeight() - node.getStackHeight() <= 2.0) {
                            temp.isDiagonally(true);
                            if (!adj.contains(temp))
                                adj.add(temp);
                        }
                    }
                }
            }
            if ((x > 0) && (y > 0)) {
                RoomTile offX = this.findTile(openList, (short) (x - 1), y);
                RoomTile offY = this.findTile(openList, x, (short) (y - 1));
                if (offX != null && offY != null && (offX.isWalkable() || offY.isWalkable())) {
                    RoomTile temp = this.findTile(openList, (short) (x - 1), (short) (y - 1));
                    if (this.canWalkOn(temp, unit)) {
                        if (temp.state != RoomTileState.SIT || nextTile.getStackHeight() - node.getStackHeight() <= 2.0) {
                            temp.isDiagonally(true);
                            if (!adj.contains(temp))
                                adj.add(temp);
                        }
                    }
                }
            }
            if ((x > 0) && (y < this.mapSizeY)) {
                RoomTile offX = this.findTile(openList, (short) (x - 1), y);
                RoomTile offY = this.findTile(openList, x, (short) (y + 1));
                if (offX != null && offY != null && (offX.isWalkable() || offY.isWalkable())) {
                    RoomTile temp = this.findTile(openList, (short) (x - 1), (short) (y + 1));
                    if (this.canWalkOn(temp, unit)) {
                        if (temp.state != RoomTileState.SIT || nextTile.getStackHeight() - node.getStackHeight() <= 2.0) {
                            temp.isDiagonally(true);
                            if (!adj.contains(temp))
                                adj.add(temp);
                        }
                    }
                }
            }
            if ((x < this.mapSizeX) && (y > 0)) {
                RoomTile offX = this.findTile(openList, (short) (x + 1), y);
                RoomTile offY = this.findTile(openList, x, (short) (y - 1));
                if (offX != null && offY != null && (offX.isWalkable() || offY.isWalkable())) {
                    RoomTile temp = this.findTile(openList, (short) (x + 1), (short) (y - 1));
                    if (this.canWalkOn(temp, unit)) {
                        if (temp.state != RoomTileState.SIT || nextTile.getStackHeight() - node.getStackHeight() <= 2.0) {
                            temp.isDiagonally(true);
                            if (!adj.contains(temp))
                                adj.add(temp);
                        }
                    }
                }
            }
        }
        return adj;
    }

    private boolean canWalkOn(RoomTile tile, RoomUnit unit) {
        return tile != null && (unit.canOverrideTile(tile) || (tile.state != RoomTileState.BLOCKED && tile.state != RoomTileState.INVALID));
    }
}

public class PathCheck {
    public static void main(String[] args) throws Exception {
        BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
        PrintStream out = new PrintStream(new BufferedOutputStream(System.out));
        RoomLayout layout = null; Room room = null;
        String line;
        while ((line = in.readLine()) != null) {
            String[] p = line.split(" ");
            switch (p[0]) {
                case "ROOM":
                    room = new Room(); room.walkthrough = p[5].equals("1");
                    layout = new RoomLayout(p[1].replace("|", "\r"), Short.parseShort(p[2]), Short.parseShort(p[3]), Integer.parseInt(p[4]), room);
                    room.layout = layout;
                    break;
                case "STATE": layout.getTile(Short.parseShort(p[1]), Short.parseShort(p[2])).state = RoomTileState.valueOf(p[3]); break;
                case "UNIT": layout.getTile(Short.parseShort(p[1]), Short.parseShort(p[2])).units[0]++; break;
                case "STACK": layout.getTile(Short.parseShort(p[1]), Short.parseShort(p[2])).setStackHeight(Double.parseDouble(p[3])); break;
                case "PATH": {
                    RoomTile a = layout.getTile(Short.parseShort(p[1]), Short.parseShort(p[2]));
                    RoomTile b = layout.getTile(Short.parseShort(p[3]), Short.parseShort(p[4]));
                    Deque<RoomTile> path = layout.findPath(a, b, b, new RoomUnit(), false);
                    if (path == null) { out.println("NULL"); break; }
                    StringBuilder sb = new StringBuilder("P");
                    for (RoomTile t2 : path) sb.append(' ').append(t2.x).append(',').append(t2.y);
                    out.println(sb);
                    break;
                }
            }
        }
        out.flush();
    }
}
