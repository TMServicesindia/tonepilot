# Instrument recognition — proxy benchmark (synthetic; NOT real film-music accuracy)

Test bank: GeneralUser GS renders (incl. TonePilot imitation tones). Train bank (thresholds, heads): FluidR3 GM (MIT).
Different sample sets, same instrument names. Exact = right instrument; family = right family; unknown = abstained.

## Solo clips (original)

| System | Exact | Family | Wrong family | Unknown | Source (acoustic/electronic/imitation) |
|---|---|---|---|---|---|
| A · clap | 0% | 0% | 0% | 100% | 28% |
| C · clap + head | 15% | 25% | 59% | 16% | 60% |
| A · efficientat | 1% | 10% | 90% | 0% | 57% |
| C · efficientat + head | 59% | 75% | 25% | 0% | 81% |
| A · panns | 3% | 5% | 0% | 95% | 60% |
| C · panns + head | 54% | 70% | 30% | 0% | 79% |
| A · panns10 | 1% | 10% | 1% | 89% | 67% |
| C · panns10 + head | 53% | 67% | 33% | 0% | 78% |
| A · yamnet | 0% | 9% | 3% | 88% | 63% |
| C · yamnet + head | 52% | 65% | 35% | 0% | 81% |

## Robustness (family accuracy by variant; exact in brackets)

| System | Original | Reverb | Compressed | Short (1 s) | Imitation tones (family) |
|---|---|---|---|---|---|
| A · clap | 0% (0%) | 0% (0%) | 0% (0%) | 0% (0%) | 0% |
| C · clap + head | 25% (15%) | 37% (24%) | 34% (23%) | 24% (13%) | 28% |
| A · efficientat | 10% (1%) | 10% (1%) | 10% (1%) | 10% (1%) | 5% |
| C · efficientat + head | 75% (59%) | 76% (63%) | 72% (56%) | 69% (51%) | 68% |
| A · panns | 5% (3%) | 7% (5%) | 6% (4%) | 17% (10%) | 7% |
| C · panns + head | 70% (54%) | 71% (56%) | 69% (54%) | 69% (49%) | 72% |
| A · panns10 | 10% (1%) | 15% (3%) | 9% (1%) | 17% (5%) | 3% |
| C · panns10 + head | 67% (53%) | 68% (53%) | 60% (47%) | 67% (50%) | 60% |
| A · yamnet | 9% (0%) | 17% (0%) | 9% (0%) | 20% (1%) | 3% |
| C · yamnet + head | 65% (52%) | 75% (57%) | 67% (54%) | 67% (50%) | 67% |

## Layered tracks (2–4 instruments, timed entries)

| System | Window instrument P/R/F1 | Window family P/R/F1 | Track instrument P/R/F1 | Median start+end error | Events found |
|---|---|---|---|---|---|
| A · clap | 0.00/0.00/0.00 | 0.21/0.88/0.34 | 0.00/0.00/0.00 | – | 0 |
| C · clap + head | 0.11/0.10/0.11 | 0.26/0.18/0.21 | 0.14/0.17/0.15 | 4.0 s | 15 |
| A · efficientat | 0.04/0.52/0.07 | 0.15/0.87/0.26 | 0.05/0.47/0.09 | 1.5 s | 33 |
| C · efficientat + head | 0.46/0.20/0.28 | 0.59/0.50/0.54 | 0.38/0.50/0.43 | 3.2 s | 42 |
| A · panns | 0.17/0.13/0.14 | 0.36/0.41/0.39 | 0.19/0.30/0.23 | 5.0 s | 21 |
| C · panns + head | 0.34/0.21/0.26 | 0.54/0.43/0.48 | 0.31/0.57/0.41 | 8.0 s | 48 |
| A · panns10 | 0.13/0.12/0.12 | 0.34/0.32/0.33 | 0.15/0.30/0.20 | 8.0 s | 22 |
| C · panns10 + head | 0.36/0.20/0.26 | 0.54/0.46/0.50 | 0.28/0.53/0.37 | 6.5 s | 46 |
| A · yamnet | 0.29/0.07/0.11 | 0.33/0.17/0.22 | 0.22/0.19/0.20 | 11.5 s | 19 |
| C · yamnet + head | 0.26/0.18/0.22 | 0.48/0.47/0.47 | 0.24/0.57/0.33 | 3.5 s | 49 |

## Per family (original solo clips; family / exact)

| System | Bass | Bells | Electronic | Indian plucked | Indian winds | Keys | Other | Other percussion | Other plucked | Other winds | Strings | Western winds |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A · clap | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% |
| C · clap + head | 67% / 67% | 81% / 33% | 15% / 15% | 27% / 20% | 38% / 21% | 5% / 0% | 5% / 0% | 100% / 100% | 0% / 0% | 22% / 22% | 10% / 10% | 13% / 13% |
| A · efficientat | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 100% / 14% | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% |
| C · efficientat + head | 67% / 67% | 81% / 67% | 78% / 56% | 67% / 60% | 75% / 54% | 81% / 52% | 67% / 52% | 100% / 100% | 90% / 57% | 0% / 0% | 93% / 83% | 60% / 53% |
| A · panns | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 5% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 30% / 20% | 7% / 7% |
| C · panns + head | 0% / 0% | 81% / 56% | 89% / 59% | 87% / 67% | 71% / 58% | 57% / 48% | 81% / 57% | 100% / 100% | 38% / 24% | 33% / 33% | 83% / 70% | 53% / 53% |
| A · panns10 | 0% / 0% | 11% / 0% | 4% / 0% | 0% / 0% | 0% / 0% | 19% / 0% | 0% / 0% | 100% / 0% | 10% / 0% | 0% / 0% | 23% / 7% | 13% / 0% |
| C · panns10 + head | 0% / 0% | 78% / 59% | 81% / 56% | 100% / 73% | 58% / 50% | 62% / 57% | 76% / 57% | 100% / 100% | 48% / 48% | 0% / 0% | 73% / 57% | 60% / 47% |
| A · yamnet | 0% / 0% | 19% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 5% / 0% | 0% / 0% | 0% / 0% | 0% / 0% | 27% / 0% | 40% / 0% |
| C · yamnet + head | 0% / 0% | 78% / 63% | 63% / 44% | 67% / 53% | 67% / 58% | 57% / 43% | 76% / 62% | 100% / 100% | 57% / 43% | 33% / 22% | 77% / 70% | 53% / 33% |

## Model facts (CI runner CPU)

| Model | Parameters | Seconds per audio minute | Load s |
|---|---|---|---|
| clap | 68611864 | 5.32 | 8.6 |
| efficientat | 4876831 | 0.44 | 2.8 |
| panns | 81837071 | 2.51 | 442.4 |
| panns10 | 6302735 | 2.0 | 52.3 |
| yamnet | – | 0.63 | 5.8 |

Not covered (no licensed audio yet): viola, tabla, mridangam, dholak, ghatam, kanjira, thavil, dhol.
