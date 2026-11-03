// Runs Nitro's avatar TypeScript (bundled by esbuild) on the cases; writes out/js.json.
// node test/run_js.js <data folder>   (the folder has data/ (XML) and assets.json, see README)
const fs = require('fs');
const path = require('path');
const xml = require('./xml');
const A = require('../out/avatar.js');
const { cases } = require('./cases');

const dir = process.argv[2];
const read = (f) => xml.parse(fs.readFileSync(path.join(dir, 'data', f), 'latin1'));
const assets = JSON.parse(fs.readFileSync(path.join(dir, 'assets.json'), 'utf8'));
const data = {
    geometry: read('geometry.txt'), partSets: read('partsets.txt'), animation: read('animation.txt'),
    actions: read('actions.xml'), offsets: { lay: read('offset_lay.txt'), swim: read('offset_swim.txt') },
    figureData: [ read('figure.txt'), read('figuredata.xml') ]
};
const renderer = A.createRenderer(data, { get: (name) => assets[name] || null });
const out = [];
for(const c of cases)
{
    const avatar = renderer.createImage(c.figure, c.scale);
    A.setState(avatar, c);
    const frames = [];
    for(let i = 0; i < c.frames; i++)
    {
        frames.push(A.frame(avatar));
        A.next(avatar);
    }
    out.push(frames);
}
fs.mkdirSync(path.join(__dirname, '..', 'out'), { recursive: true });
fs.writeFileSync(path.join(__dirname, '..', 'out', 'js.json'), JSON.stringify(out));
console.log('js: ' + out.length + ' cases');
