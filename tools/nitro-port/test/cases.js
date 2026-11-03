const models = require('../data/habbo_models.json');
const cases = [];
for (const m of models) {
  for (const [entry, ft, wt] of [[true,1,1],[false,1,1],[true,0.5,0.25],[true,2,2],[true,0,0]]) {
    cases.push({ name: m.name + (entry ? '' : ' noentry') + ` ft${ft} wt${wt}`, model: m.heightmap, wallHeight: -1, ex: entry ? m.door_x : -1, ey: entry ? m.door_y : -1, ft, wt });
  }
}
// edge cases: fixed wall height, small rooms, stairs and holes in the middle, door on a raised tile
const extra = [
  ['tiny 1x1', 'xxx\rx0x\rxxx'], ['one row', 'xxxxx\r00000\rxxxxx'], ['stairs', 'xxxxxx\rx3210x\rx3210x\r00000x\rx0000x\rxxxxxx'],
  ['hole', 'xxxxxx\rx0000x\rx0xx0x\rx0000x\r00000x\rxxxxxx'], ['raised door', 'xxxx\rx22x\r222x\rx22x\rxxxx'], ['letters', 'xxxx\rxabx\rxzzx\rxxxx'],
  ['ragged rows', 'xxxxx\rx000\rx00000x\r000\rxxxxxxx'], ['no door', 'xxxx\rx00x\rx00x\rxxxx'], ['empty row', 'xxxx\r\rx00x\rxxxx']
];
for (const [n, m] of extra) for (const wh of [-1, 0, 5]) cases.push({ name: n + ' wh' + wh, model: m, wallHeight: wh, ex: -1, ey: -1, ft: 1, wt: 1 });
module.exports = cases;
