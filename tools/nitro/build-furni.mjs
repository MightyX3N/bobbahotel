// Builds every furni in content/furni/catalogue.json into what Nitro and Arcturus need:
//   <out>/bundled/furniture/<id>.nitro       the furni's pictures and data (Nitro's furni format)
//   <out>/dcr/hof_furni/icons/<id>_icon.png  its catalogue and inventory icon
//   <out>/gamedata/FurnitureData.json        the furni list the client reads
//   <out>/sql/furni.sql                      items_base and catalogue rows for Arcturus
//
//   node tools/nitro/build-furni.mjs [out dir] [sprites dir]
//
// The catalogue says what each furni is (decided by hand). Where a picture stands is measured
// from the picture itself: the bottom edge of a floor furni is the V of its footprint's front
// sides, which gives its tiles and the point where it touches the floor. Like Habbo's own furni,
// every picture is then pinned to the centre of the furni's back tile (asset x/y), pictures drawn
// a little off our tile size are resized to fit their tiles, and rugs are stretched to cover them.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { alignExact, blank, blit, box, crop, encode, half, load, transformed } from './png.mjs';
import { writeBundle } from './bundle.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));
const out = process.argv[2] ?? join(root, 'build', 'nitro');
const spritesDir = process.argv[3] ?? join(root, 'sprites');
const catalogue = JSON.parse(readFileSync(join(root, 'content', 'furni', 'catalogue.json'), 'utf8')).items;

for (const d of ['bundled/furniture', 'dcr/hof_furni/icons', 'gamedata', 'sql']) mkdirSync(join(out, d), { recursive: true });

/** Habbo direction (0/2/4/6) -> degrees, as Nitro's furni logic wants them. */
const DEGREES = { 0: 0, 2: 90, 4: 180, 6: 270 };
/** How high you sit on a seat and lie on a bed (height steps), see the avatar figure's sit/lay pictures. */
const SIT_HEIGHT = 0.6;
const LAY_HEIGHT = 0.6;
/** How high wall shelves hang (in tiles of height); furni on them stand at this height. */
const SHELF_HEIGHT = 1.5;

// ---- measuring ----

/** The V of a floor picture's bottom edge: front corner (fx, fy), left/right corners' x, top. */
function measureFloor(img) {
  const cols = [];
  let top = img.height;
  for (let x = 0; x < img.width; x++) {
    let b = -1;
    for (let y = 0; y < img.height; y++) if (img.data[(y * img.width + x) * 4 + 3] > 200) { b = y; top = Math.min(top, y); }
    if (b >= 0) cols.push([x, b]);
  }
  if (cols.length === 0) return null;
  let fx = cols[0][0], fy = Infinity;
  for (let x = cols[0][0]; x <= cols.at(-1)[0]; x += 0.5) {
    let y = -Infinity;
    for (const [cx, b] of cols) y = Math.max(y, b + Math.abs(cx - x) / 2);
    if (y < fy - 1e-9) [fx, fy] = [x, y];
  }
  const touching = cols.filter(([cx, b]) => fy - Math.abs(cx - fx) / 2 - b <= 2).map(([cx]) => cx);
  return { fx, fy: fy + 1, left: Math.min(...touching), right: Math.max(...touching) + 1, top };
}

/**
 * Tiles [along x, along y] (for this picture's direction), scale or stretch to fit them, the
 * footprint's middle in the picture, and the height in height steps.
 */
function fitFloor(img, flat) {
  const m = measureFloor(img);
  if (!m) return { size: [1, 1], m: [1, 0, 0, 1], at: [img.width / 2, img.height], height: 0 };
  const w = Math.max(0, (m.fx - m.left) / 32);
  const l = Math.max(0, (m.right - m.fx) / 32);
  let size = [1, 1];
  let scale = 1;
  let stretch = [1, 1];
  if (flat) {
    size = [Math.max(1, Math.round(w)), Math.max(1, Math.round(l))];
    stretch = [size[0] / Math.max(0.2, w), size[1] / Math.max(0.2, l)];
  } else if (w + l >= 1.2) {
    let best = null;
    for (let W = 1; W <= 8; W++) {
      for (let L = 1; L <= 8; L++) {
        const fit = Math.min(W / Math.max(w, 0.1), L / Math.max(l, 0.1));
        const sc = fit < 1 ? fit : fit <= 1.12 ? fit : 1;
        const empty = (W - Math.min(W, w * sc)) / W + (L - Math.min(L, l * sc)) / L;
        const err = 0.5 * Math.abs(Math.log(sc)) + empty;
        if (!best || err < best.err - 1e-9) best = { W, L, sc, err };
      }
    }
    size = [best.W, best.L];
    scale = best.sc;
  } else if (w > 1 || l > 1) {
    scale = Math.min(1 / Math.max(w, 0.1), 1 / Math.max(l, 0.1));
  }
  if (Math.abs(scale - 1) < 0.02) scale = 1;
  const yAt = (x) => m.fy - Math.abs(x - m.fx) / 2;
  const at = [(m.left + m.right) / 2, (yAt(m.left) + yAt(m.right)) / 2];
  const height = flat ? 0 : Math.max(0, Math.round(((at[1] - m.top) / 32 - (w + l) / 4) * scale * 10) / 10);
  // Stretching along the floor's own x and y (tiles are 32 px across and 16 down per tile along x,
  // -32 and 16 along y): on screen that is this matrix; then the uniform scale.
  const [sx, sy] = stretch;
  const mat = [((sx + sy) / 2) * scale, ((sx - sy) / 4) * scale, (sx - sy) * scale, ((sx + sy) / 2) * scale];
  return { size, m: mat, at, height, measured: [w, l] };
}

/** Is a wall picture drawn for a back wall (edges running down to the right)? */
function forBackWall(img) {
  const edge = (fromTop) => {
    const e = [];
    for (let x = 0; x < img.width; x++) {
      let found = null;
      for (let i = 0; i < img.height; i++) {
        const y = fromTop ? i : img.height - 1 - i;
        if (img.data[(y * img.width + x) * 4 + 3] > 200) { found = y; break; }
      }
      e.push(found);
    }
    return e;
  };
  let down = 0, up = 0;
  for (const e of [edge(true), edge(false)]) {
    for (let x = 0; x + 2 < e.length; x++) {
      if (e[x] === null || e[x + 2] === null) continue;
      if (e[x + 2] - e[x] === 1) down++;
      else if (e[x] - e[x + 2] === 1) up++;
    }
  }
  return down >= up;
}

// ---- lining up a direction's pictures ----

/**
 * All pictures of one direction (every state and frame) on one canvas: the pack's files for one
 * furni come in different canvas sizes, so each is matched onto the first picture pixel by pixel.
 * Returns { pictures: [[img]] per state, offsets of each in the first picture's pixels }.
 */
function lineUp(states) {
  const imgs = states.map((frames) => frames.map((f) => load(join(spritesDir, 'furni', `${f}.png`))));
  const ref = imgs[0][0];
  const refSolid = box(ref, 200) ?? [0, 0, ref.width, ref.height];
  const offsets = imgs.map((frames) =>
    frames.map((img) => {
      if (img === ref) return [0, 0];
      // The pack draws a furni's animation frames on one canvas: those stay where they are.
      if (img.width === ref.width && img.height === ref.height) return [0, 0];
      // The solid part (no glow or light beam) the same size: the same thing in another state
      // (a window with its shutters closed), so the solid parts go exactly on top of each other.
      const b = box(img, 200) ?? [0, 0, img.width, img.height];
      if (b[2] - b[0] === refSolid[2] - refSolid[0] && b[3] - b[1] === refSolid[3] - refSolid[1]) return [refSolid[0] - b[0], refSolid[1] - b[1]];
      const [dx, dy, share] = alignExact(ref, img);
      if (share >= 0.35) return [dx, dy];
      // Too different to match pixel by pixel (a present opened, a book laid down): stand them
      // on the same spot, the middle of the bottom of the solid part.
      return [Math.round((refSolid[0] + refSolid[2]) / 2 - (b[0] + b[2]) / 2), refSolid[3] - b[3]];
    }),
  );
  // Every picture on one shared canvas, so all of them are cut, scaled and pinned the same way.
  const all = imgs.flatMap((frames, s) => frames.map((img, f) => [img, offsets[s][f]]));
  const minX = Math.min(...all.map(([, [x]]) => x)), minY = Math.min(...all.map(([, [, y]]) => y));
  const maxX = Math.max(...all.map(([img, [x]]) => x + img.width)), maxY = Math.max(...all.map(([img, [, y]]) => y + img.height));
  const placed = imgs.map((frames, s) =>
    frames.map((img, f) => {
      const c = blank(maxX - minX, maxY - minY);
      blit(img, c, offsets[s][f][0] - minX, offsets[s][f][1] - minY);
      return { img: c, at: [minX, minY], first: s === 0 && f === 0 };
    }),
  );
  return { ref, placed };
}

/** A crop box grown so that it starts on even pixels (the half-size pictures then line up too). */
const even = ([l, t, r, b]) => [l - (l & 1), t - (t & 1), r, b];

// ---- building ----

const furnidata = { roomitemtypes: { furnitype: [] }, wallitemtypes: { furnitype: [] } };
const sql = [];
const report = [];
const PAGES = [
  ['Living Room', /sofa|armchair|chair|table|cushion|pillow|stool|coffee|bookcase|cupboard|night table|drawer|wardrobe|closet/i],
  ['Bedroom', /bed|mattress/i],
  ['Kitchen', /kitchen|cooker|hob|fridge|oven|microwave|toaster|kettle|dish|bowl|mug|cup|glass|tumbler|fork|spoon|knife|pan|pot|sugar|toast|cereal|soda|cola|bottle|wine|teapot|coffee machine|cutting|sponge/i],
  ['Bathroom', /bath|toilet|shower|soap|towel|washbasin|tap|sink|tissues|toilet roll/i],
  ['Office', /desk|office|binder|printer|copier|shredder|keyboard|pc|computer|monitor|laptop|paper|notebook|ruler|pencil|calculator|telephone|whiteboard|board|filing|server|projector|oscilloscope|multimeter|welder|circuit|microscope|filament|drawing/i],
  ['Electronics', /console|kitsune|orbit|vortex|hayate|comet|tv|speaker|headphones|screen|camera|robot|vacuum|thermostat|ac|air|switch/i],
  ['Lighting', /lamp|lantern|light|candle/i],
  ['Plants', /plant|cactus|palm|aloe|bonsai|sunflower|tree/i],
  ['Rugs', /rug|mat\b|runner/i],
  ['Walls & Windows', /window|wall|partition|stair|railing|torii|pipe|cable|vent/i],
  ['Decoration', /poster|sign|map|painting|art|portrait|photo|diploma|blueprint|chart|scroll|mirror|clock|note|book|vase|duck|present|parcel|box/i],
];
/**
 * Starting price in credits (owners change prices on the admin pages): small things are cheap,
 * big ones cost more, seats and beds a little extra.
 */
function price(item, [w, l], height) {
  const base = 2 + 3 * w * l + Math.round(2 * Math.min(height, 3));
  return Math.max(2, Math.min(30, base + (item.sit ? 2 : 0) + (item.lay ? 4 : 0)));
}

const pageOf = (name) => (PAGES.find(([, re]) => re.test(name)) ?? ['Other'])[0];
const pages = new Map();

for (const item of catalogue) {
  const id = item.id;
  const wall = item.kind === 'wall';
  const assets = {};
  const images = {}; // sprite sheet frame name -> picture
  const visDirs = {};
  const animations = {};
  let stateCount = 1;
  let animated = false;
  let size = item.size ?? [1, 1];
  let height = item.height ?? 0;
  let logicZ = 1;
  let icon = null;
  const own = Object.keys(item.pics).map(Number);

  /** Adds one direction's pictures (Nitro direction `dir`), pinned so that `pin(picture)` gives asset x/y. */
  const addDirection = (dir, states, place) => {
    const { placed } = lineUp(states);
    let frameId = 0;
    placed.forEach((frames, s) => {
      const ids = frames.map(({ img, at, first }) => {
        const { img: drawn, x, y } = place(img, at, first);
        const name = `${id}_64_a_${dir}_${frameId}`;
        assets[name] = { x, y };
        images[`${id}_${name}`] = drawn;
        if (!icon) icon = drawn;
        return frameId++;
      });
      if (ids.length > 1) animated = true;
      const anim = (animations[s] ??= { layers: { 0: { frameSequences: { 0: { frames: {} } } } } });
      const layer = anim.layers[0];
      if (ids.length > 1) {
        layer.loopCount = item.once ? 1 : 0;
        layer.frameRepeat = Math.max(1, Math.round(24 / (item.fps ?? 8)));
      }
      ids.forEach((fid, i) => (layer.frameSequences[0].frames[i] = { id: fid }));
    });
    stateCount = Math.max(stateCount, placed.length);
    visDirs[dir] = {};
  };

  /** A direction drawn as another one mirrored. */
  const mirror = (dir, from) => {
    for (const [name, a] of Object.entries({ ...assets })) {
      const m = new RegExp(`^${id}_64_a_${from}_(\\d+)$`).exec(name);
      if (m) assets[`${id}_64_a_${dir}_${m[1]}`] = { source: name, flipH: true, x: a.x, y: a.y };
    }
    visDirs[dir] = {};
  };

  if (item.kind === 'shelf') {
    // A wall shelf that holds furni (Habbo's way): a floor item on the tiles along a wall, drawn
    // SHELF_HEIGHT up against the wall; furni put on its tiles stand on the board. Direction 4 is
    // along the back wall (x), 2 along the left wall (y).
    const [key] = own;
    const first = load(join(spritesDir, 'furni', `${item.pics[key][0][0]}.png`));
    const nitroDir = forBackWall(first) ? 4 : 2;
    const len = item.len ?? 1;
    let mid = null;
    addDirection(nitroDir, item.pics[key], (img, at, isFirst) => {
      const b = even(box(img) ?? [0, 0, img.width, img.height]);
      if (isFirst || !mid) {
        const fb = box(img) ?? b;
        // The board's middle: the middle of the picture, a little up (the board's front edge).
        mid = [(fb[0] + fb[2]) / 2, (fb[1] + fb[3]) / 2 - 2];
      }
      const drawn = crop(img, b);
      // Where it goes from the middle of the first tile: half-way along the shelf, 0.3 tile
      // towards the wall, SHELF_HEIGHT up.
      const along = (len - 1) / 2;
      const ox = nitroDir === 4 ? 32 * along + 9.6 : -32 * along - 9.6;
      const oy = 16 * along - 4.8 - 32 * SHELF_HEIGHT;
      void at;
      return { img: drawn, x: Math.round(mid[0] - b[0] - ox), y: Math.round(mid[1] - b[1] - oy) };
    });
    mirror(nitroDir === 4 ? 2 : 4, nitroDir);
    size = [len, 1];
    height = SHELF_HEIGHT;
    logicZ = SHELF_HEIGHT + 0.2;
  } else if (wall) {
    // Our own picture is drawn for one wall: Nitro's direction 4 is the right-hand (back) wall,
    // 2 the left wall. The other wall gets it mirrored.
    const [key] = own;
    const first = load(join(spritesDir, 'furni', `${item.pics[key][0][0]}.png`));
    const nitroDir = forBackWall(first) ? 4 : 2;
    const depth = item.depth ?? 0;
    let w = 0, h = 0, mid = null;
    addDirection(nitroDir, item.pics[key], (img, at, isFirst) => {
      // Pinned by the middle of the first picture (its middle on the wall, for things that stick
      // out); every state is on the same canvas, so they all use that same point.
      const b = even(box(img) ?? [0, 0, img.width, img.height]);
      if (isFirst || !mid) {
        const fb = box(img) ?? b;
        [w, h] = [fb[2] - fb[0], fb[3] - fb[1]];
        mid = [(fb[0] + fb[2]) / 2, (fb[1] + fb[3]) / 2];
      }
      const drawn = crop(img, b);
      const dx = nitroDir === 4 ? 16 * depth : -16 * depth;
      void at;
      return { img: drawn, x: Math.round(mid[0] - b[0] + dx), y: Math.round(mid[1] - b[1] - 8 * depth) };
    });
    mirror(nitroDir === 4 ? 2 : 4, nitroDir);
    size = [Math.max(0.2, w / 32 - depth), 0];
    logicZ = Math.max(0.2, (h - w / 2) / 32);
  } else {
    // Each direction with its own pictures is measured on its first picture.
    const fits = {};
    for (const d of own) fits[d] = fitFloor(load(join(spritesDir, 'furni', `${item.pics[d][0][0]}.png`)), !!item.walk);
    const main = fits[4] ? 4 : fits[2] ? 2 : own[0];
    const f = fits[main];
    const [a, b] = f.size;
    size = item.size ?? (main === 2 || main === 6 ? [b, a] : [a, b]);
    height = item.height ?? f.height;
    for (const d of own) {
      const fit = fits[d];
      const [W, L] = d === 2 || d === 6 ? [size[1], size[0]] : size;
      addDirection(d, item.pics[d], (img, at) => {
        // The footprint's middle in this picture, then through the scale/stretch.
        const centre = [fit.at[0] - at[0], fit.at[1] - at[1]];
        const t = transformed(img, fit.m, centre);
        const b = even(box(t.img) ?? [0, 0, 1, 1]);
        const drawn = crop(t.img, b);
        const cx = t.point[0] - b[0], cy = t.point[1] - b[1];
        // Pinned at the centre of the back tile: the footprint's middle minus half the footprint.
        return { img: drawn, x: Math.round(cx - (W - L) * 16), y: Math.round(cy - (W + L - 2) * 8) };
      });
    }
    // Missing directions: 2 is 4 mirrored, 6 and 0 each other mirrored.
    if (own.includes(4) && !own.includes(2)) mirror(2, 4);
    if (own.includes(2) && !own.includes(4)) mirror(4, 2);
    if (own.includes(0) && !own.includes(6)) mirror(6, 0);
    if (own.includes(6) && !own.includes(0)) mirror(0, 6);
    logicZ = Math.max(0.1, height);
    report.push(`${id}\t${f.measured?.map((v) => v.toFixed(2)).join('x')}\t-> ${size.join('x')}\th${height}`);
  }

  // The zoomed-out view (size 32): every picture at half size, pinned at half the point.
  for (const [name, a] of Object.entries({ ...assets })) {
    const small = name.replace(`${id}_64_`, `${id}_32_`);
    if (a.source) assets[small] = { ...a, source: a.source.replace(`${id}_64_`, `${id}_32_`), x: Math.round(a.x / 2), y: Math.round(a.y / 2) };
    else {
      assets[small] = { x: Math.round(a.x / 2), y: Math.round(a.y / 2) };
      images[`${id}_${small}`] = half(images[`${id}_${name}`]);
    }
  }

  // Seats facing away from the viewer (0 and 6): whoever sits there has their back to us, so the
  // seat's back is in front of them. The picture is drawn closer than the sitter (Habbo does this
  // with a separate backrest layer).
  if (item.sit) for (const d of [0, 6]) if (visDirs[d]) visDirs[d] = { layers: { 0: { z: -0.5 } } };

  const dirs = Object.keys(visDirs).map(Number).sort((p, q) => p - q);
  const multi = stateCount > 1 || animated;
  // Rugs and other flat things you walk on are drawn behind everything standing on their tiles
  // (pushed back by their own length, as if they were at their back corner), but in front of the
  // shadows (which Nitro draws 1 back).
  const flatZ = item.walk && !item.sit ? 1.2 + size[0] + size[1] : 0;
  const vis = (s) => ({ size: s, layerCount: 1, angle: 45, layers: { 0: { z: flatZ } }, directions: visDirs, ...(multi ? { animations } : {}) });
  const data = {
    name: id,
    type: id,
    logicType: item.logic ?? (stateCount > 1 ? 'furniture_multistate' : 'furniture_basic'),
    visualizationType: multi ? 'furniture_animated' : 'furniture_static',
    logic: { model: { dimensions: { x: size[0], y: size[1], z: logicZ }, directions: dirs.map((d) => DEGREES[d]) } },
    assets,
    visualizations: [vis(32), vis(64)],
  };
  writeBundle(join(out, 'bundled', 'furniture', `${id}.nitro`), id, data, images);

  // Icon: the first picture, at most 50 px.
  if (icon) {
    const k = Math.min(1, 50 / Math.max(icon.width, icon.height));
    const small = k < 1 ? transformed(icon, [k, 0, 0, k], [0, 0]).img : icon;
    writeFileSync(join(out, 'dcr', 'hof_furni', 'icons', `${id}_icon.png`), encode(small));
    item.iconPicture = icon;
  }

  // Furni list (client) and items_base + catalogue (server).
  const entry = {
    id: item.sprite, classname: id, revision: 1, category: 'other', defaultdir: 0, xdim: wall ? 1 : size[0], ydim: wall ? 1 : size[1],
    partcolors: { color: [] }, name: item.name, description: '', adurl: '', offerid: -1, buyout: false, rentofferid: -1, rentbuyout: false,
    bc: false, excludeddynamic: false, customparams: '', specialtype: 1, canstandon: !!item.walk, cansiton: !!item.sit, canlayon: !!item.lay,
    furniline: 'bobba', environment: '', rare: false,
  };
  (wall ? furnidata.wallitemtypes : furnidata.roomitemtypes).furnitype.push(entry);
  const stackHeight = item.sit ? SIT_HEIGHT : item.lay ? LAY_HEIGHT : item.walk ? 0 : height;
  const esc = (s) => s.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
  sql.push(
    `(${item.sprite},${item.sprite},'${esc(item.name)}','${id}','${wall ? 'i' : 's'}',${wall ? 0 : size[0]},${wall ? 0 : size[1]},${stackHeight.toFixed(2)},` +
      `${item.stack && !wall ? 1 : 0},${item.sit ? 1 : 0},${item.lay ? 1 : 0},${item.walk ? 1 : 0},'${esc(item.interaction ?? 'default')}',${stateCount})`,
  );
  item.price = price(item, wall ? [1, 1] : size, height);
  // Hidden furni (the gift parcel) aren't sold.
  if (!item.hidden) {
    const page = wall && pageOf(item.name) === 'Other' ? 'Walls & Windows' : pageOf(item.name);
    (pages.get(page) ?? pages.set(page, []).get(page)).push(item);
  }
}

// Floor and wall styles (from build-generic.mjs): bought as Habbo's "floor" and "wallpaper" items,
// whose catalogue name ends in the style's code.
const paintsFile = join(out, 'gamedata', 'paints.json');
const paints = existsSync(paintsFile) ? JSON.parse(readFileSync(paintsFile, 'utf8')) : { floors: {}, walls: {} };
const PAINT = { wallpaper: [9901, 3001, 'Wallpaper'], floor: [9902, 3002, 'Floor'], landscape: [9903, 4055, 'Landscape'] };
for (const [classname, [, sprite, name]] of Object.entries(PAINT)) {
  furnidata.wallitemtypes.furnitype.push({
    id: sprite, classname, revision: 1, category: classname, defaultdir: 0, xdim: 1, ydim: 1, partcolors: { color: [] }, name, description: '',
    adurl: '', offerid: -1, buyout: false, rentofferid: -1, rentbuyout: false, bc: false, excludeddynamic: false, customparams: '', specialtype: 1,
    canstandon: false, cansiton: false, canlayon: false, furniline: 'bobba', environment: '', rare: false,
  });
}
const PAINT_PRICE = 3;

writeFileSync(join(out, 'gamedata', 'FurnitureData.json'), JSON.stringify(furnidata));
// The SQL can run on every deploy: it adds new furni and catalogue entries and updates what the
// furni are, but keeps the prices owners set on the admin pages.
const q = (v) => (typeof v === 'number' ? String(v) : `'${String(v).replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`);
const offers = []; // [catalog_name, item_ids, page_id, credits, order]
const pageRows = [`(9000,-1,'bobba','Furni','default_3x3',9000,1,1,'1','1','','','')`];
let pageId = 9001;
/** A catalogue page's icon (c_images/catalogue/icon_<page>.png): a furni from it, at most 22 px. */
const pageIcon = (pid, picture) => {
  const k = Math.min(1, 22 / Math.max(picture.width, picture.height));
  const img = k < 1 ? transformed(picture, [k, 0, 0, k], [0, 0]).img : picture;
  writeFileSync(join(out, 'c_images', 'catalogue', `icon_${pid}.png`), encode(img));
};
// The furni each page shows as its icon (the page's first one when it isn't listed here).
const ICON_FURNI = { Office: 'bobba_office_main_chair', 'Living Room': 'bobba_sofa_1', Bedroom: 'bobba_bed_g_4', Kitchen: 'bobba_fridge', Bathroom: 'bobba_wc_front_1', Lighting: 'bobba_lamp_10', Plants: 'bobba_plant_2', Rugs: 'bobba_carpet_modern', 'Walls & Windows': 'bobba_window_11', Decoration: 'bobba_wall_clock' };
mkdirSync(join(out, 'c_images', 'catalogue'), { recursive: true });
for (const [name, items] of pages) {
  const pid = pageId++;
  const shown = items.find((it) => it.id === ICON_FURNI[name] && it.iconPicture) ?? items.find((it) => it.iconPicture);
  if (shown) pageIcon(pid, shown.iconPicture);
  if (shown && name === 'Living Room') pageIcon(9000, shown.iconPicture);
  pageRows.push(`(${pid},9000,${q(name.toLowerCase().replace(/[^a-z]+/g, '_'))},${q(name)},'default_3x3',${pid},1,${pid - 9000},'1','1','','','')`);
  items.forEach((it, i) => offers.push([it.id, it.sprite, pid, it.price, i + 1]));
}
pageRows.push(`(9050,-1,'spaces','Floors & Walls','spaces_new',9050,1,2,'1','1','','','Floors and wallpapers for your rooms: try them on in the preview, then buy.')`);
Object.keys(paints.floors).forEach((code, i) => offers.push([`floor_single_${code}`, PAINT.floor[0], 9050, PAINT_PRICE, i + 1]));
Object.keys(paints.walls).forEach((code, i) => offers.push([`wallpaper_single_${code}`, PAINT.wallpaper[0], 9050, PAINT_PRICE, 100 + i + 1]));

const BASE_COLS = 'id,sprite_id,public_name,item_name,type,width,length,stack_height,allow_stack,allow_sit,allow_lay,allow_walk,interaction_type,interaction_modes_count';
const update = (cols) => cols.split(',').filter((c) => c !== 'id').map((c) => `${c}=VALUES(${c})`).join(',');
const PAGE_COLS = 'id,parent_id,caption_save,caption,page_layout,icon_image,min_rank,order_num,visible,enabled,page_headline,page_teaser,page_text1';
writeFileSync(
  join(out, 'sql', 'furni.sql'),
  [
    '-- Bobba Hotel furni and catalogue (built by tools/nitro/build-furni.mjs; safe to run again).',
    `INSERT INTO items_base (${BASE_COLS}) VALUES\n${sql.join(',\n')}\nON DUPLICATE KEY UPDATE ${update(BASE_COLS)};`,
    `INSERT INTO items_base (${BASE_COLS}) VALUES\n${Object.entries(PAINT).map(([cls, [id, sprite, name]]) => `(${id},${sprite},'${name}','${cls}','i',0,0,1.00,0,0,0,0,'roomeffect',1)`).join(',\n')}\nON DUPLICATE KEY UPDATE ${update(BASE_COLS)};`,
    `INSERT INTO catalog_pages (${PAGE_COLS}) VALUES\n${pageRows.join(',\n')}\nON DUPLICATE KEY UPDATE ${update(PAGE_COLS)};`,
    'UPDATE catalog_pages SET icon_image=9100 WHERE id=9100;',
    `DELETE FROM catalog_pages WHERE id >= 9000 AND id < 9100 AND id NOT IN (${pageRows.map((r) => r.slice(1, r.indexOf(','))).join(',')});`,
    `DELETE FROM catalog_items WHERE page_id >= 9000 AND page_id < 9100 AND catalog_name NOT IN (${offers.map((o) => q(o[0])).join(',')});`,
    ...offers.map(([name, item, page, credits, order]) =>
      `UPDATE catalog_items SET item_ids=${q(String(item))}, page_id=${page}, order_number=${order} WHERE catalog_name=${q(name)} AND page_id >= 9000 AND page_id < 9100;\n` +
      `INSERT INTO catalog_items (item_ids,page_id,catalog_name,cost_credits,cost_points,points_type,amount,order_number,offer_id) SELECT ${q(String(item))},${page},${q(name)},${credits},0,0,1,${order},-1 FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM catalog_items WHERE catalog_name=${q(name)} AND page_id >= 9000 AND page_id < 9100);`,
    ),
    '',
  ].join('\n'),
);
writeFileSync(join(out, 'furni-measured.txt'), report.join('\n') + '\n');
console.log(`${catalogue.length} furni built into ${out}`);
