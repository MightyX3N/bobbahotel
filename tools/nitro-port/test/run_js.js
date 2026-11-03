const n = require('../out/nitro.js'); const cases = require('./cases.js');
const out = {};
for (const c of cases) {
  const room = n.build(c.model, c.wallHeight, true, c.ex, c.ey, c.ft, c.wt);
  // the camera: every plane corner on screen at both zooms, and a click back onto each plane's middle
  const cam = {};
  for (const s of [64, 32]) {
    const g = n.create(s); const pts = [];
    for (const p of room.planes) {
      for (const [a, b] of [[0,0],[1,0],[0,1],[1,1]]) pts.push(g.screen(p.loc[0] + p.left[0]*a + p.right[0]*b, p.loc[1] + p.left[1]*a + p.right[1]*b, p.loc[2] + p.left[2]*a + p.right[2]*b));
      const mid = g.screen(p.loc[0] + (p.left[0] + p.right[0]) / 3, p.loc[1] + (p.left[1] + p.right[1]) / 3, p.loc[2] + (p.left[2] + p.right[2]) / 3);
      pts.push(mid ? g.planePosition(mid[0], mid[1], p.loc, p.left, p.right) : null);
    }
    cam[s] = pts;
  }
  room.camera = cam;
  room.view = { 64: n.planes(room, 64), 32: n.planes(room, 32) };
  // the mouse on a grid over the room, at both zooms
  room.picks = {};
  for (const s of [64, 32]) {
    const v = room.view[s]; const res = [];
    if (v.length && c.ft === 1 && c.wt === 1) {
      const xs = v.flatMap(p => [p.a[0], p.b[0], p.c[0], p.d[0]]), ys = v.flatMap(p => [p.a[1], p.b[1], p.c[1], p.d[1]]);
      for (let y = Math.min(...ys) - 3; y <= Math.max(...ys) + 3; y += 7) for (let x = Math.min(...xs) - 3; x <= Math.max(...xs) + 3; x += 9) res.push(n.pick(room, v, s, x + 0.25, y + 0.5));
    }
    room.picks[s] = res;
  }
  out[c.name] = room;
}
require('fs').writeFileSync(__dirname + '/../out/js.json', JSON.stringify(out));
console.log(cases.length, 'cases');
