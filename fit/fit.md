# Tone fit (T3) on the DEV tone bench — independent judges

Rendered GM audio (DEV banks), not real songs. 'Applied' = the app's nearest-sound check kept the fit.
Judged against the part alone (no leakage). CNN10 gain = cosine(fitted, part) − cosine(plain, part) for the parts where the fit was applied; better = gain > 0.002; worse = gain < −0.01.

| Group | Parts | Fit applied | CNN10 better | CNN10 worse (< −0.01) | Worst | Mean CNN10 gain | MFCC closer | Mean MFCC gain |
|---|---|---|---|---|---|---|---|---|
| same · asis · backing | 12 | 0 | 0/0 | 0 | +0.000 | +0.0000 | 0/0 | +0.000 |
| same · asis · lead | 12 | 3 | 0/3 | 0 | -0.007 | -0.0033 | 0/3 | -0.290 |
| same · performed · backing | 12 | 0 | 0/0 | 0 | +0.000 | +0.0000 | 0/0 | +0.000 |
| same · performed · lead | 12 | 5 | 4/5 | 0 | -0.009 | +0.0180 | 3/5 | +0.153 |
| timgm · asis · backing | 12 | 0 | 0/0 | 0 | +0.000 | +0.0000 | 0/0 | +0.000 |
| timgm · asis · lead | 12 | 3 | 1/3 | 0 | -0.005 | +0.0054 | 1/3 | -0.179 |
| timgm · performed · backing | 12 | 0 | 0/0 | 0 | +0.000 | +0.0000 | 0/0 | +0.000 |
| timgm · performed · lead | 12 | 6 | 5/6 | 0 | +0.001 | +0.0303 | 6/6 | +0.383 |
| **All (as the app plays it)** | 96 | 17 | 10/17 | 0 | -0.009 | +0.0164 | 10/17 | +0.097 |
| All, ungated (every fit applied) | 96 | 27 | 15/27 | 3 | -0.077 | +0.0089 | 16/27 | +0.176 |

**Pre-registered gate:** CNN10 better in ≥ 50 % of applied fits and none worse by > 0.01 → PASS (10/17 better, 0 worse).
