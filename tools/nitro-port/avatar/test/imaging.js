// The same 48 avatars bobba_habbo_imaging saved from Habbo, drawn by the port: out/imaging.json
const fs = require('fs');
const path = require('path');
const xml = require('./xml');
const A = require('../out/avatar.js');
const dir = process.argv[2];
const read = (f) => xml.parse(fs.readFileSync(path.join(dir, 'data', f), 'latin1'));
const assets = JSON.parse(fs.readFileSync(path.join(dir, 'assets.json'), 'utf8'));
const r = A.createRenderer({ geometry: read('geometry.txt'), partSets: read('partsets.txt'), animation: read('animation.txt'),
    actions: read('actions.xml'), offsets: { lay: read('offset_lay.txt'), swim: read('offset_swim.txt') },
    figureData: [ read('figure.txt'), read('figuredata.xml') ] }, { get: (n) => assets[n] || null });
const fig = 'hr-100-61.hd-180-1.ch-210-66.lg-270-82.sh-290-80';
const base = { posture: 'std', postureParameter: '', gesture: 0, dance: 0, sign: -1, carryObject: 0, useObject: 0, talk: false, sleep: false, blink: false, expression: 0, effect: 0 };
const out = {};
for(let d = 0; d < 8; d++)
{
    const kinds = {
        std: {}, sit: { posture: 'sit' }, lay: { posture: 'lay' }, head: { headDirection: (d + 1) % 8 }, crr: { carryObject: 2 }, sml: { gesture: 1 }
    };
    for(const k in kinds)
    {
        const a = r.createImage(fig, 'h');
        A.setState(a, Object.assign({}, base, { direction: d, headDirection: d }, kinds[k]));
        out[k + '_' + d] = A.frame(a);
    }
}
fs.writeFileSync(path.join(__dirname, '..', 'out', 'imaging.json'), JSON.stringify(out));
