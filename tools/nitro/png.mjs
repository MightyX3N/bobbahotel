// Small picture helpers on top of pngjs: load, measure, resize, stretch, place on a canvas.
import { readFileSync } from 'node:fs';
import { PNG } from 'pngjs';

/** A picture: width, height and RGBA bytes. */
export function load(file) {
  const p = PNG.sync.read(readFileSync(file));
  return { width: p.width, height: p.height, data: p.data };
}

export function blank(width, height) {
  return { width, height, data: Buffer.alloc(width * height * 4) };
}

export function alphaAt(img, x, y) {
  if (x < 0 || y < 0 || x >= img.width || y >= img.height) return 0;
  return img.data[(y * img.width + x) * 4 + 3];
}

/** Visible box [left, top, right, bottom) of pixels with alpha above `min`, or null. */
export function box(img, min = 16) {
  let l = img.width, t = img.height, r = -1, b = -1;
  for (let y = 0; y < img.height; y++) {
    for (let x = 0; x < img.width; x++) {
      if (img.data[(y * img.width + x) * 4 + 3] > min) {
        if (x < l) l = x;
        if (x > r) r = x;
        if (y < t) t = y;
        if (y > b) b = y;
      }
    }
  }
  return r < 0 ? null : [l, t, r + 1, b + 1];
}

/**
 * Draws `img` through the 2x2 matrix m (picture pixels -> output pixels, around the point
 * `from` in the picture, which lands on `to` in the output), nearest pixel. Returns a new picture
 * of the given size.
 */
export function transform(img, m, from, to, width, height) {
  const out = blank(width, height);
  const [a, b, c, d] = m; // x' = a x + c y, y' = b x + d y
  const det = a * d - b * c;
  const [ia, ib, ic, id] = [d / det, -b / det, -c / det, a / det];
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const dx = x + 0.5 - to[0];
      const dy = y + 0.5 - to[1];
      const sx = Math.floor(ia * dx + ic * dy + from[0]);
      const sy = Math.floor(ib * dx + id * dy + from[1]);
      if (sx < 0 || sy < 0 || sx >= img.width || sy >= img.height) continue;
      img.data.copy(out.data, (y * width + x) * 4, (sy * img.width + sx) * 4, (sy * img.width + sx) * 4 + 4);
    }
  }
  return out;
}

/** The picture through matrix m, cropped to what's visible; returns it and where `point` ended up. */
export function transformed(img, m, point) {
  const [a, b, c, d] = m;
  const corners = [[0, 0], [img.width, 0], [0, img.height], [img.width, img.height]].map(([x, y]) => [
    a * (x - point[0]) + c * (y - point[1]),
    b * (x - point[0]) + d * (y - point[1]),
  ]);
  const minX = Math.floor(Math.min(...corners.map((p) => p[0])));
  const minY = Math.floor(Math.min(...corners.map((p) => p[1])));
  const maxX = Math.ceil(Math.max(...corners.map((p) => p[0])));
  const maxY = Math.ceil(Math.max(...corners.map((p) => p[1])));
  const to = [-minX, -minY];
  return { img: transform(img, m, point, to, maxX - minX, maxY - minY), point: to };
}

/** Crops a picture to [l, t, r, b). */
export function crop(img, [l, t, r, b]) {
  const out = blank(r - l, b - t);
  for (let y = t; y < b; y++) img.data.copy(out.data, ((y - t) * out.width) * 4, (y * img.width + l) * 4, (y * img.width + r) * 4);
  return out;
}

/** Copies `img` into `dst` at (x, y). */
export function blit(img, dst, x, y) {
  for (let r = 0; r < img.height; r++) {
    const ty = y + r;
    if (ty < 0 || ty >= dst.height) continue;
    for (let c = 0; c < img.width; c++) {
      const tx = x + c;
      if (tx < 0 || tx >= dst.width) continue;
      const s = (r * img.width + c) * 4;
      if (img.data[s + 3] === 0) continue;
      img.data.copy(dst.data, (ty * dst.width + tx) * 4, s, s + 4);
    }
  }
}

/**
 * Half size, for Nitro's zoomed-out view (32 px tiles): each 2x2 block becomes its most
 * opaque pixel (the top-left one when they tie), which keeps pixel art crisp.
 */
export function half(img) {
  const out = blank(Math.max(1, Math.ceil(img.width / 2)), Math.max(1, Math.ceil(img.height / 2)));
  for (let y = 0; y < out.height; y++) {
    for (let x = 0; x < out.width; x++) {
      let best = -1, bestA = -1;
      for (const [dx, dy] of [[0, 0], [1, 0], [0, 1], [1, 1]]) {
        const sx = 2 * x + dx, sy = 2 * y + dy;
        if (sx >= img.width || sy >= img.height) continue;
        const i = (sy * img.width + sx) * 4;
        if (img.data[i + 3] > bestA) { bestA = img.data[i + 3]; best = i; }
      }
      if (best >= 0) img.data.copy(out.data, (y * out.width + x) * 4, best, best + 4);
    }
  }
  return out;
}

/** A picture filled with one colour [r, g, b, a?]. */
export function solid(width, height, [r, g, b, a = 255]) {
  const out = blank(width, height);
  for (let i = 0; i < width * height; i++) out.data.set([r, g, b, a], i * 4);
  return out;
}

export function encode(img) {
  const p = new PNG({ width: Math.max(1, img.width), height: Math.max(1, img.height) });
  if (img.width && img.height) img.data.copy(p.data);
  return PNG.sync.write(p);
}

/**
 * Where `img` best lies over `ref` (the offset of img's top-left in ref's pixels): the shift that
 * makes the most solid pixels match in colour. Used to line up a furni's state pictures, whose
 * files have different canvas sizes. Returns [dx, dy, share of img's solid pixels that matched].
 */
export function align(ref, img) {
  const solid = [];
  for (let y = 0; y < img.height; y++) {
    for (let x = 0; x < img.width; x++) if (img.data[(y * img.width + x) * 4 + 3] > 200) solid.push([x, y]);
  }
  if (solid.length === 0) return [0, 0, 0];
  // Sample at most ~1500 pixels for speed.
  const step = Math.max(1, Math.floor(solid.length / 1500));
  const pts = solid.filter((_, i) => i % step === 0);
  const dxs = [Math.min(0, ref.width - img.width) - 24, Math.max(0, ref.width - img.width) + 24];
  const dys = [Math.min(0, ref.height - img.height) - 24, Math.max(0, ref.height - img.height) + 24];
  let best = [0, 0, -1];
  for (let dy = dys[0]; dy <= dys[1]; dy++) {
    for (let dx = dxs[0]; dx <= dxs[1]; dx++) {
      let hit = 0;
      for (const [x, y] of pts) {
        const rx = x + dx, ry = y + dy;
        if (rx < 0 || ry < 0 || rx >= ref.width || ry >= ref.height) continue;
        const i = (ry * ref.width + rx) * 4, j = (y * img.width + x) * 4;
        if (ref.data[i + 3] < 200) continue;
        if (Math.abs(ref.data[i] - img.data[j]) + Math.abs(ref.data[i + 1] - img.data[j + 1]) + Math.abs(ref.data[i + 2] - img.data[j + 2]) < 40) hit++;
      }
      // Ties: prefer the shift closest to lining up the bottom middles.
      const bias = -0.001 * (Math.abs(dx - (ref.width - img.width) / 2) + Math.abs(dy - (ref.height - img.height)));
      if (hit + bias > best[2]) best = [dx, dy, hit + bias];
    }
  }
  return [best[0], best[1], Math.max(0, best[2]) / pts.length];
}
