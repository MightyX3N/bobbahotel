// What each furni is put through (the same in run_js.js and run_lua.py): every direction Habbo has
// (and an odd one), every state (and one past the last), colours, and 24 updates of 50 ms each time.
// A state is the furni's animation number; how many there are comes from its visualization.
function timeline(stateCount)
{
    const steps = [];
    for(const direction of [ 0, 2, 4, 6, 1 ])
    {
        for(let state = 0; state <= stateCount; state++)
        {
            steps.push({ direction: direction * 45, state: state, color: state % 3, updates: 24 });
        }
    }
    return steps;
}

// Park-Miller: exact in both languages, so Nitro's Math.random() gives the same numbers in each
function random(seed)
{
    let s = seed;
    return () => { s = (s * 16807) % 2147483647; return s / 2147483647; };
}

module.exports = { timeline, random, STEP_MS: 50, START_MS: 100000 };
