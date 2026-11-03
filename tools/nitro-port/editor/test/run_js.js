// Runs the action script (test/script.json) through nitro-react's editor logic: one state per step
const fs = require('fs');
const { Editor } = require('../out/editor.js');
const [ , , xmlPath, scriptPath, outPath ] = process.argv;
const xml = fs.readFileSync(xmlPath, 'utf8');
const script = JSON.parse(fs.readFileSync(scriptPath, 'utf8'));
let r = 0;
Math.random = () => script.random[(r++) % script.random.length];
const states = [];
for(const run of script.runs)
{
    r = 0;
    const ed = new Editor(xml, run.club);
    for(const s of run.steps)
    {
        try
        {
            switch(s.op)
            {
                case 'load': ed.loadAvatarInEditor(s.figure, s.gender); break;
                case 'part': { const m = ed.model(s.model); const c = m.categories.get(s.cat); m.selectPart(s.cat, s.index % c.parts.length); break; }
                case 'color': { const m = ed.model(s.model); const c = m.categories.get(s.cat); const p = c.getPalette(s.palette); if(p && p.length) m.selectColor(s.cat, s.index % p.length, s.palette); break; }
                case 'gender': ed.setGender(s.gender); break;
                case 'clear': ed.clear(); break;
                case 'reset': ed.reset(); break;
                case 'random': ed.randomize(); break;
            }
            states.push(ed.state());
        }
        catch(e) { states.push({ error: String(e) }); }
    }
}
fs.writeFileSync(outPath, JSON.stringify(states));
console.log('js:', states.length, 'states');
