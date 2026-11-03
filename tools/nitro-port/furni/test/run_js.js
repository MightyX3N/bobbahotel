// Runs Nitro's furniture TypeScript (bundled by esbuild) on every furni in out/furni.json; writes
// out/js.json.        node test/run_js.js
const fs = require('fs');
const path = require('path');
const xml = require('../../avatar/test/xml');
const { timeline, random, STEP_MS, START_MS } = require('./cases');

const out = [];
const furni = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'out', 'furni.json'), 'utf8'));
Math.random = random(1);
const F = require('../out/furni.js');
for(const f of furni)
{
    const lib = f.name;
    const trees = {};
    for(const k of Object.keys(f.xml)) trees[k] = xml.parse(f.xml[k]);
    const type = F.loadType(trees, { get: (name) => { const s = f.sizes[lib + '_' + name]; return s ? { width: s[0], height: s[1] } : null; } });
    if(!type) { out.push({ name: lib, failed: true }); continue; }
    const states = stateCount(f.xml.visualization);
    const furniObj = F.create(type);
    const frames = [];
    let time = START_MS;
    for(const step of timeline(states))
    {
        F.setState(furniObj, { direction: step.direction, state: step.state, color: step.color, time: time });
        for(let i = 0; i < step.updates; i++)
        {
            F.update(furniObj, time);
            frames.push(F.sprites(furniObj));
            time += STEP_MS;
        }
    }
    out.push({ name: lib, visualizationType: type.visualizationType, frames: frames });
}

function stateCount(text)
{
    let top = -1;
    const re = /<animation(\s[^>]*)>/g;
    let m;
    while((m = re.exec(text)) !== null)
    {
        const id = /\sid="(\d+)"/.exec(m[1]);
        if(id && m[1].indexOf('transition') < 0 && +id[1] < 1000 && +id[1] > top) top = +id[1];
    }
    return Math.max(1, top + 1);
}

fs.writeFileSync(path.join(__dirname, '..', 'out', 'js.json'), JSON.stringify(out));
console.log('js: ' + out.length + ' furni, ' + out.reduce((n, f) => n + (f.frames ? f.frames.length : 0), 0) + ' frames');
