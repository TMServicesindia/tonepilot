# Blend by leakage-aware spectral unmixing — pre-registered gate (first run, no tuning)

| Group | Targets | >1 layer | CNN10 better | Worse < −0.01 | Worse < −0.02 | Mean gain | True 2nd instrument found | True lead kept |
|---|---|---|---|---|---|---|---|---|
| same · blend | 12 | 12 | 7/12 | 3 | 2 | +0.0206 | 2 | 5 |
| same · single | 12 | 10 | 3/12 | 4 | 4 | -0.0029 | 0 | 8 |
| timgm · blend | 12 | 9 | 6/12 | 3 | 2 | +0.0217 | 1 | 2 |
| timgm · single | 12 | 10 | 2/12 | 7 | 7 | -0.0276 | 0 | 4 |

**Gate:** A 13/24 ✓ · B 11 ✗ · C 15 ✗ → **FAIL**
