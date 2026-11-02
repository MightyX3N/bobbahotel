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
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { align, blank, blit, box, crop, encode, half, load, transformed } from './png.mjs';
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
  const placed = imgs.map((frames) =>
    frames.map((img) => {
      if (img === ref) return { img, at: [0, 0] };
      if (img.width === ref.width && img.height === ref.height) return { img, at: [0, 0] };
      const [dx, dy, share] = align(ref, img);
      if (share < 0.25) {
        // Too different to match (a present opening): line up their bottom middles.
        return { img, at: [Math.round((ref.width - img.width) / 2), ref.height - img.height] };
      }
      return { img, at: [dx, dy] };
    }),
  );
  return { ref, placed };
}

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
      const ids = frames.map(({ img, at }) => {
        const { img: drawn, x, y } = place(img, at);
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

  if (wall) {
    // Our own picture is drawn for one wall: Nitro's direction 4 is the right-hand (back) wall,
    // 2 the left wall. The other wall gets it mirrored.
    const [key] = own;
    const first = load(join(spritesDir, 'furni', `${item.pics[key][0][0]}.png`));
    const nitroDir = forBackWall(first) ? 4 : 2;
    const depth = item.depth ?? 0;
    let w = 0, h = 0;
    addDirection(nitroDir, item.pics[key], (img, at) => {
      // Pinned by the middle of the picture (its middle on the wall, for things that stick out).
      const b = box(img) ?? [0, 0, img.width, img.height];
      const drawn = crop(img, b);
      if (img === first || (!w && !h)) [w, h] = [drawn.width, drawn.height];
      const cx = drawn.width / 2, cy = drawn.height / 2;
      const dx = nitroDir === 4 ? 16 * depth : -16 * depth;
      void at;
      return { img: drawn, x: Math.round(cx + dx), y: Math.round(cy - 8 * depth) };
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
        const b = box(t.img) ?? [0, 0, 1, 1];
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

  const dirs = Object.keys(visDirs).map(Number).sort((p, q) => p - q);
  const multi = stateCount > 1 || animated;
  const vis = (s) => ({ size: s, layerCount: 1, angle: 45, layers: { 0: { z: 0 } }, directions: visDirs, ...(multi ? { animations } : {}) });
  const data = {
    name: id,
    type: id,
    logicType: stateCount > 1 ? 'furniture_multistate' : 'furniture_basic',
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
      `${item.stack && !wall ? 1 : 0},${item.sit ? 1 : 0},${item.lay ? 1 : 0},${item.walk ? 1 : 0},'default',${stateCount})`,
  );
  const page = wall && pageOf(item.name) === 'Other' ? 'Walls & Windows' : pageOf(item.name);
  (pages.get(page) ?? pages.set(page, []).get(page)).push(item);
}

writeFileSync(join(out, 'gamedata', 'FurnitureData.json'), JSON.stringify(furnidata));
const pageRows = [];
const itemRows = [];
let pageId = 9001;
pageRows.push(`(9000,-1,'bobba','Furni','default_3x3',1,1,1,'1','1')`);
for (const [name, items] of pages) {
  const pid = pageId++;
  pageRows.push(`(${pid},9000,'${name.toLowerCase().replace(/[^a-z]+/g, '_')}','${name.replace(/'/g, "\\'")}','default_3x3',1,1,${pid - 9000},'1','1')`);
  items.forEach((it, i) => itemRows.push(`('${it.sprite}',${pid},'${it.id}',0,0,0,1,${i + 1},-1)`));
}
writeFileSync(
  join(out, 'sql', 'furni.sql'),
  [
    '-- Bobba Hotel furni (built by tools/nitro/build-furni.mjs). Replaces the hotel furni and their catalogue.',
    'DELETE FROM catalog_items WHERE page_id >= 9000 AND page_id < 9100;',
    'DELETE FROM catalog_pages WHERE id >= 9000 AND id < 9100;',
    'DELETE FROM items_base WHERE id >= 10000 AND id < 20000;',
    `INSERT INTO items_base (id,sprite_id,public_name,item_name,type,width,length,stack_height,allow_stack,allow_sit,allow_lay,allow_walk,interaction_type,interaction_modes_count) VALUES\n${sql.join(',\n')};`,
    `INSERT INTO catalog_pages (id,parent_id,caption_save,caption,page_layout,icon_image,min_rank,order_num,visible,enabled) VALUES\n${pageRows.join(',\n')};`,
    `INSERT INTO catalog_items (item_ids,page_id,catalog_name,cost_credits,cost_points,points_type,amount,order_number,offer_id) VALUES\n${itemRows.join(',\n')};`,
    '',
  ].join('\n'),
);
writeFileSync(join(out, 'furni-measured.txt'), report.join('\n') + '\n');
console.log(`${catalogue.length} furni built into ${out}`);
