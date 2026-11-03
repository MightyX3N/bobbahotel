// The avatars both sides draw: figures, directions, postures, gestures, animation frames.
const FIGURES = [
    'hr-100-61.hd-180-1.ch-210-66.lg-270-82.sh-290-80',
];
const cases = [];
for(const figure of FIGURES)
{
    for(let dir = 0; dir < 8; dir++)
    {
        for(const posture of [ 'std', 'mv', 'sit', 'lay' ])
        {
            for(const gesture of [ 0 ])
            {
                cases.push({ figure, scale: 'h', direction: dir, headDirection: dir, posture, postureParameter: '', gesture, dance: 0, sign: -1, carryObject: 0, useObject: 0, talk: false, sleep: false, blink: false, expression: 0, effect: 0, frames: 8 });
            }
        }
        cases.push({ figure, scale: 'h', direction: dir, headDirection: dir, posture: 'std', postureParameter: '', gesture: 0, dance: 0, sign: -1, carryObject: 0, useObject: 0, talk: true, sleep: false, blink: false, expression: 1, effect: 0, frames: 8 });
        cases.push({ figure, scale: 'h', direction: dir, headDirection: (dir + 1) % 8, posture: 'std', postureParameter: '', gesture: 0, dance: 0, sign: 3, carryObject: 2, useObject: 0, talk: false, sleep: true, blink: false, expression: 0, effect: 0, frames: 4 });
    }
}
module.exports = { cases };
