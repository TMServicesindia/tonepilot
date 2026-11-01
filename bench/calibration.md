# Gate 1 — calibrated abstention (synthetic proxy; NOT real film-music accuracy)

Thresholds chosen on DEV (FluidR3 phrase 2 + layered 16–23) for wrong-family ≤ 5% at maximum coverage; heads trained on TRAIN (FluidR3 phrases 0–1 + layered 0–15); TEST = GeneralUser GS, untouched.

## TEST, original solo clips

| System | DEV target met | Coverage | Selective family acc. | Selective exact acc. | Exact overall | Wrong family | Unknown |
|---|---|---|---|---|---|---|---|
| A-argmax · clap | n/a (always answers) | 100% | 7% | 3% | 3% | 93% | 0% |
| A · clap | yes | 0% | – | – | 0% | 0% | 100% |
| C · clap + head | yes | 3% | 57% | 20% | 0% | 1% | 97% |
| A-argmax · efficientat | n/a (always answers) | 100% | 10% | 1% | 1% | 90% | 0% |
| A · efficientat | NO | 100% | 10% | 1% | 1% | 90% | 0% |
| C · efficientat + head | yes | 72% | 86% | 80% | 36% | 10% | 28% |
| A-argmax · panns | n/a (always answers) | 100% | 47% | 26% | 26% | 53% | 0% |
| A · panns | yes | 31% | 65% | 42% | 12% | 11% | 69% |
| C · panns + head | yes | 85% | 70% | 56% | 45% | 26% | 15% |
| A-argmax · yamnet | n/a (always answers) | 100% | 48% | 26% | 26% | 52% | 0% |
| A · yamnet | yes | 27% | 79% | 51% | 13% | 6% | 73% |
| C · yamnet + head | yes | 55% | 80% | 65% | 23% | 11% | 45% |

## TEST by condition (coverage / wrong family / selective family accuracy)

| System | Original | Reverb | Compressed | Short 1 s | Imitation tones |
|---|---|---|---|---|---|
| A-argmax · clap | 100% / 93% / 7% | 100% / 93% / 7% | 100% / 93% / 7% | 100% / 93% / 7% | 100% / 80% / 20% |
| A · clap | 0% / 0% / – | 0% / 0% / – | 0% / 0% / – | 0% / 0% / – | 0% / 0% / – |
| C · clap + head | 3% / 1% / 57% | 20% / 12% / 39% | 31% / 16% / 48% | 7% / 4% / 44% | 14% / 9% / 33% |
| A-argmax · efficientat | 100% / 90% / 10% | 100% / 90% / 10% | 100% / 90% / 10% | 100% / 90% / 10% | 100% / 95% / 5% |
| A · efficientat | 100% / 90% / 10% | 100% / 90% / 10% | 100% / 90% / 10% | 100% / 90% / 10% | 100% / 95% / 5% |
| C · efficientat + head | 72% / 10% / 86% | 74% / 12% / 83% | 69% / 10% / 85% | 95% / 25% / 73% | 78% / 22% / 72% |
| A-argmax · panns | 100% / 53% / 47% | 100% / 50% / 50% | 100% / 56% / 44% | 100% / 54% / 46% | 100% / 77% / 23% |
| A · panns | 31% / 11% / 65% | 38% / 13% / 65% | 32% / 11% / 65% | 33% / 11% / 67% | 34% / 20% / 41% |
| C · panns + head | 85% / 26% / 70% | 85% / 24% / 72% | 78% / 19% / 76% | 100% / 37% / 63% | 88% / 24% / 73% |
| A-argmax · yamnet | 100% / 52% / 48% | 100% / 49% / 51% | 100% / 56% / 44% | 100% / 52% / 48% | 100% / 85% / 15% |
| A · yamnet | 27% / 6% / 79% | 33% / 6% / 82% | 25% / 6% / 76% | 19% / 5% / 76% | 15% / 10% / 32% |
| C · yamnet + head | 55% / 11% / 80% | 61% / 11% / 83% | 49% / 9% / 82% | 71% / 25% / 65% | 63% / 21% / 67% |

## Coverage curve on TEST (family accuracy of the most confident share; reporting only)

| System | 100% | 90% | 80% | 70% | 60% | 50% | 30% |
|---|---|---|---|---|---|---|---|
| A-argmax · clap | 12% | 13% | 13% | 15% | 8% | 8% | 12% |
| A · clap | 12% | 13% | 13% | 15% | 8% | 8% | 12% |
| C · clap + head | 22% | 22% | 23% | 26% | 25% | 28% | 35% |
| A-argmax · efficientat | 1% | 2% | 2% | 2% | 2% | 3% | 5% |
| A · efficientat | 1% | 2% | 2% | 2% | 2% | 3% | 5% |
| C · efficientat + head | 72% | 78% | 82% | 82% | 87% | 87% | 94% |
| A-argmax · panns | 52% | 55% | 58% | 58% | 59% | 60% | 63% |
| A · panns | 52% | 55% | 58% | 58% | 59% | 60% | 63% |
| C · panns + head | 75% | 78% | 79% | 78% | 82% | 86% | 91% |
| A-argmax · yamnet | 51% | 54% | 57% | 61% | 66% | 69% | 82% |
| A · yamnet | 51% | 54% | 57% | 61% | 66% | 69% | 82% |
| C · yamnet + head | 75% | 79% | 81% | 85% | 85% | 87% | 89% |

## NSynth TEST (real recorded/synthesised notes, CC BY 4.0; different source; family level only)

| System | Coverage | Selective family acc. | Wrong family | Unknown |
|---|---|---|---|---|
| A-argmax · clap | 100% | 0% | 100% | 0% |
| A · clap | 0% | – | 0% | 100% |
| C · clap + head | 13% | 42% | 7% | 87% |
| A-argmax · efficientat | 100% | 26% | 74% | 0% |
| A · efficientat | 100% | 26% | 74% | 0% |
| C · efficientat + head | 50% | 87% | 7% | 50% |
| A-argmax · panns | 100% | 27% | 73% | 0% |
| A · panns | 1% | 33% | 1% | 99% |
| C · panns + head | 25% | 79% | 5% | 75% |
| A-argmax · yamnet | 100% | 40% | 60% | 0% |
| A · yamnet | 8% | 56% | 4% | 92% |
| C · yamnet + head | 25% | 82% | 4% | 75% |

## Layered tracks on TEST (window thresholds from DEV)

| System | Window instrument P/R/F1 | Window family P/R/F1 | Events detected | Onset error median / p90 | Offset error median / p90 | Instrument F1 by #instruments |
|---|---|---|---|---|---|---|
| A · clap | 0.00/0.00/0.00 | 0.21/0.88/0.34 | 0/70 | – / – | – / – | 2: 0.00, 3: 0.00, 4: 0.00 |
| C · clap + head | 0.11/0.13/0.12 | 0.24/0.32/0.28 | 14/70 | 3.0 s / 5.0 s | 2.0 s / 6.0 s | 2: 0.12, 3: 0.09, 4: 0.15 |
| A · efficientat | 0.04/0.52/0.07 | 0.15/0.87/0.26 | 33/70 | 0.0 s / 1.5 s | 0.0 s / 1.5 s | 2: 0.06, 3: 0.07, 4: 0.07 |
| C · efficientat + head | 0.41/0.29/0.34 | 0.50/0.49/0.50 | 46/70 | 0.5 s / 7.0 s | 0.5 s / 2.8 s | 2: 0.34, 3: 0.32, 4: 0.35 |
| A · panns | 0.19/0.11/0.14 | 0.36/0.41/0.39 | 19/70 | 1.0 s / 12.0 s | 0.5 s / 12.1 s | 2: 0.14, 3: 0.17, 4: 0.12 |
| C · panns + head | 0.27/0.32/0.29 | 0.48/0.50/0.49 | 45/70 | 0.5 s / 7.1 s | 0.5 s / 10.4 s | 2: 0.33, 3: 0.29, 4: 0.26 |
| A · yamnet | 0.29/0.07/0.11 | 0.33/0.17/0.22 | 13/70 | 2.0 s / 11.9 s | 0.5 s / 11.2 s | 2: 0.15, 3: 0.13, 4: 0.07 |
| C · yamnet + head | 0.28/0.20/0.23 | 0.43/0.49/0.46 | 40/70 | 1.0 s / 5.7 s | 0.8 s / 8.5 s | 2: 0.23, 3: 0.24, 4: 0.22 |

## Source type on TEST (C heads; truth -> predicted)

- **C · clap + head**: acoustic -> acoustic: 74; acoustic -> electronic: 3; acoustic -> imitation: 46; electronic -> acoustic: 12; electronic -> electronic: 5; electronic -> imitation: 16; imitation -> acoustic: 25; imitation -> electronic: 1; imitation -> imitation: 34
- **C · efficientat + head**: acoustic -> acoustic: 116; acoustic -> electronic: 1; acoustic -> imitation: 6; electronic -> acoustic: 4; electronic -> electronic: 26; electronic -> imitation: 3; imitation -> acoustic: 28; imitation -> electronic: 1; imitation -> imitation: 31
- **C · panns + head**: acoustic -> acoustic: 107; acoustic -> electronic: 4; acoustic -> imitation: 12; electronic -> acoustic: 2; electronic -> electronic: 24; electronic -> imitation: 7; imitation -> acoustic: 19; imitation -> electronic: 3; imitation -> imitation: 38
- **C · yamnet + head**: acoustic -> acoustic: 112; acoustic -> electronic: 2; acoustic -> imitation: 9; electronic -> acoustic: 7; electronic -> electronic: 23; electronic -> imitation: 3; imitation -> acoustic: 25; imitation -> electronic: 1; imitation -> imitation: 34
