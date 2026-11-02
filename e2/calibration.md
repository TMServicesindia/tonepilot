# Gate 1 — calibrated abstention (synthetic proxy; NOT real film-music accuracy)

Thresholds chosen on DEV (FluidR3 phrase 2 + layered 16–23) for wrong-family ≤ 5% at maximum coverage; heads trained on TRAIN (FluidR3 phrases 0–1 + layered 0–15); TEST = GeneralUser GS, untouched.

## TEST, original solo clips

| System | DEV target met | Coverage | Selective family acc. | Selective exact acc. | Exact overall | Wrong family | Unknown |
|---|---|---|---|---|---|---|---|
| A-argmax · clap | n/a (always answers) | 100% | 7% | 3% | 3% | 93% | 0% |
| A · clap | yes | 0% | – | – | 0% | 0% | 100% |
| C · clap + head | yes | 4% | 50% | 17% | 0% | 2% | 96% |
| C-reg · clap + head (C=0.02) | yes | 0% | – | – | 0% | 0% | 100% |
| C-agree · clap + head | yes | 25% | 36% | 25% | 6% | 16% | 75% |
| A-argmax · efficientat | n/a (always answers) | 100% | 10% | 1% | 1% | 90% | 0% |
| A · efficientat | NO | 100% | 10% | 1% | 1% | 90% | 0% |
| C · efficientat + head | yes | 72% | 86% | 80% | 36% | 10% | 28% |
| C-reg · efficientat + head (C=0.02) | yes | 78% | 83% | 81% | 37% | 13% | 22% |
| C-agree · efficientat + head | yes | 70% | 91% | 70% | 48% | 6% | 30% |
| A-argmax · panns | n/a (always answers) | 100% | 47% | 26% | 26% | 53% | 0% |
| A · panns | yes | 31% | 65% | 42% | 12% | 11% | 69% |
| C · panns + head | yes | 86% | 69% | 55% | 45% | 26% | 14% |
| C-reg · panns + head (C=0.02) | yes | 81% | 76% | 62% | 47% | 19% | 19% |
| C-agree · panns + head | yes | 69% | 84% | 64% | 42% | 11% | 31% |
| A-argmax · panns10 | n/a (always answers) | 100% | 47% | 21% | 21% | 53% | 0% |
| A · panns10 | yes | 25% | 78% | 46% | 12% | 6% | 75% |
| C · panns10 + head | yes | 59% | 85% | 73% | 25% | 9% | 41% |
| C-reg · panns10 + head (C=0.02) | yes | 75% | 76% | 55% | 35% | 18% | 25% |
| C-agree · panns10 + head | yes | 62% | 83% | 65% | 38% | 10% | 38% |
| A-argmax · yamnet | n/a (always answers) | 100% | 48% | 26% | 26% | 52% | 0% |
| A · yamnet | yes | 27% | 79% | 51% | 13% | 6% | 73% |
| C · yamnet + head | yes | 55% | 80% | 65% | 23% | 11% | 45% |
| C-reg · yamnet + head (C=0.02) | yes | 59% | 79% | 61% | 26% | 12% | 41% |
| C-agree · yamnet + head | yes | 65% | 88% | 68% | 44% | 8% | 35% |

## TEST by condition (coverage / wrong family / selective family accuracy)

| System | Original | Reverb | Compressed | Short 1 s | Imitation tones |
|---|---|---|---|---|---|
| A-argmax · clap | 100% / 93% / 7% | 100% / 93% / 7% | 100% / 93% / 7% | 100% / 93% / 7% | 100% / 80% / 20% |
| A · clap | 0% / 0% / – | 0% / 0% / – | 0% / 0% / – | 0% / 0% / – | 0% / 0% / – |
| C · clap + head | 4% / 2% / 50% | 20% / 12% / 39% | 31% / 16% / 48% | 7% / 4% / 40% | 14% / 10% / 32% |
| C-reg · clap + head (C=0.02) | 0% / 0% / – | 3% / 3% / 0% | 14% / 10% / 30% | 1% / 1% / 33% | 5% / 4% / 25% |
| C-agree · clap + head | 25% / 16% / 36% | 28% / 14% / 51% | 29% / 15% / 49% | 6% / 3% / 54% | 25% / 15% / 39% |
| A-argmax · efficientat | 100% / 90% / 10% | 100% / 90% / 10% | 100% / 90% / 10% | 100% / 90% / 10% | 100% / 95% / 5% |
| A · efficientat | 100% / 90% / 10% | 100% / 90% / 10% | 100% / 90% / 10% | 100% / 90% / 10% | 100% / 95% / 5% |
| C · efficientat + head | 72% / 10% / 86% | 73% / 12% / 84% | 69% / 10% / 85% | 95% / 25% / 74% | 77% / 22% / 72% |
| C-reg · efficientat + head (C=0.02) | 78% / 13% / 83% | 77% / 12% / 85% | 74% / 17% / 77% | 100% / 29% / 71% | 78% / 23% / 71% |
| C-agree · efficientat + head | 70% / 6% / 91% | 67% / 7% / 90% | 62% / 6% / 90% | 60% / 7% / 88% | 64% / 12% / 82% |
| A-argmax · panns | 100% / 53% / 47% | 100% / 50% / 50% | 100% / 56% / 44% | 100% / 54% / 46% | 100% / 77% / 23% |
| A · panns | 31% / 11% / 65% | 38% / 13% / 65% | 32% / 11% / 65% | 33% / 11% / 67% | 34% / 20% / 41% |
| C · panns + head | 86% / 26% / 69% | 83% / 23% / 72% | 78% / 19% / 75% | 100% / 37% / 63% | 88% / 24% / 72% |
| C-reg · panns + head (C=0.02) | 81% / 19% / 76% | 82% / 16% / 81% | 76% / 18% / 76% | 100% / 30% / 70% | 83% / 25% / 70% |
| C-agree · panns + head | 69% / 11% / 84% | 67% / 10% / 85% | 63% / 10% / 84% | 61% / 10% / 84% | 71% / 15% / 78% |
| A-argmax · panns10 | 100% / 53% / 47% | 100% / 53% / 47% | 100% / 59% / 41% | 100% / 52% / 48% | 100% / 82% / 18% |
| A · panns10 | 25% / 6% / 78% | 29% / 6% / 81% | 30% / 11% / 63% | 22% / 4% / 81% | 22% / 14% / 37% |
| C · panns10 + head | 59% / 9% / 85% | 63% / 12% / 81% | 50% / 11% / 79% | 100% / 31% / 69% | 65% / 20% / 70% |
| C-reg · panns10 + head (C=0.02) | 75% / 18% / 76% | 75% / 16% / 78% | 70% / 17% / 76% | 100% / 31% / 69% | 73% / 22% / 70% |
| C-agree · panns10 + head | 62% / 10% / 83% | 59% / 9% / 85% | 58% / 13% / 78% | 58% / 11% / 82% | 57% / 16% / 72% |
| A-argmax · yamnet | 100% / 52% / 48% | 100% / 49% / 51% | 100% / 56% / 44% | 100% / 52% / 48% | 100% / 85% / 15% |
| A · yamnet | 27% / 6% / 79% | 33% / 6% / 82% | 25% / 6% / 76% | 19% / 5% / 76% | 15% / 10% / 32% |
| C · yamnet + head | 55% / 11% / 80% | 61% / 11% / 83% | 49% / 9% / 82% | 56% / 19% / 67% | 63% / 21% / 66% |
| C-reg · yamnet + head (C=0.02) | 59% / 12% / 79% | 60% / 11% / 82% | 50% / 12% / 77% | 79% / 23% / 71% | 46% / 20% / 56% |
| C-agree · yamnet + head | 65% / 8% / 88% | 64% / 9% / 86% | 62% / 13% / 79% | 58% / 10% / 82% | 63% / 17% / 74% |

## Coverage curve on TEST (family accuracy of the most confident share; reporting only)

| System | 100% | 90% | 80% | 70% | 60% | 50% | 30% |
|---|---|---|---|---|---|---|---|
| A-argmax · clap | 12% | 13% | 13% | 15% | 8% | 8% | 12% |
| A · clap | 12% | 13% | 13% | 15% | 8% | 8% | 12% |
| C · clap + head | 22% | 22% | 23% | 25% | 25% | 28% | 35% |
| C-reg · clap + head (C=0.02) | 14% | 14% | 15% | 17% | 18% | 19% | 28% |
| C-agree · clap + head | 13% | 14% | 16% | 19% | 22% | 26% | 35% |
| A-argmax · efficientat | 1% | 2% | 2% | 2% | 2% | 3% | 5% |
| A · efficientat | 1% | 2% | 2% | 2% | 2% | 3% | 5% |
| C · efficientat + head | 72% | 78% | 82% | 82% | 87% | 87% | 94% |
| C-reg · efficientat + head (C=0.02) | 75% | 80% | 83% | 84% | 88% | 90% | 92% |
| C-agree · efficientat + head | 64% | 71% | 80% | 91% | 94% | 94% | 95% |
| A-argmax · panns | 52% | 55% | 58% | 58% | 59% | 60% | 63% |
| A · panns | 52% | 55% | 58% | 58% | 59% | 60% | 63% |
| C · panns + head | 74% | 78% | 79% | 79% | 82% | 86% | 91% |
| C-reg · panns + head (C=0.02) | 78% | 79% | 81% | 82% | 84% | 85% | 92% |
| C-agree · panns + head | 60% | 66% | 73% | 84% | 85% | 86% | 95% |
| A-argmax · panns10 | 53% | 54% | 56% | 60% | 65% | 68% | 72% |
| A · panns10 | 53% | 54% | 56% | 60% | 65% | 68% | 72% |
| C · panns10 + head | 68% | 72% | 75% | 81% | 84% | 86% | 91% |
| C-reg · panns10 + head (C=0.02) | 70% | 74% | 76% | 79% | 84% | 87% | 89% |
| C-agree · panns10 + head | 54% | 60% | 67% | 75% | 85% | 88% | 91% |
| A-argmax · yamnet | 51% | 54% | 57% | 61% | 66% | 69% | 82% |
| A · yamnet | 51% | 54% | 57% | 61% | 66% | 69% | 82% |
| C · yamnet + head | 75% | 79% | 81% | 84% | 85% | 87% | 89% |
| C-reg · yamnet + head (C=0.02) | 73% | 77% | 80% | 81% | 84% | 83% | 91% |
| C-agree · yamnet + head | 58% | 64% | 72% | 82% | 89% | 92% | 94% |

## NSynth TEST (real recorded/synthesised notes, CC BY 4.0; different source; family level only)

| System | Coverage | Selective family acc. | Wrong family | Unknown |
|---|---|---|---|---|
| A-argmax · clap | 100% | 0% | 100% | 0% |
| A · clap | 0% | – | 0% | 100% |
| C · clap + head | 13% | 42% | 7% | 87% |
| C-reg · clap + head (C=0.02) | 13% | 42% | 7% | 87% |
| C-agree · clap + head | 6% | 35% | 4% | 94% |
| A-argmax · efficientat | 100% | 26% | 74% | 0% |
| A · efficientat | 100% | 26% | 74% | 0% |
| C · efficientat + head | 50% | 87% | 7% | 50% |
| C-reg · efficientat + head (C=0.02) | 46% | 90% | 4% | 54% |
| C-agree · efficientat + head | 24% | 61% | 9% | 76% |
| A-argmax · panns | 100% | 27% | 73% | 0% |
| A · panns | 1% | 33% | 1% | 99% |
| C · panns + head | 25% | 79% | 5% | 75% |
| C-reg · panns + head (C=0.02) | 31% | 85% | 5% | 69% |
| C-agree · panns + head | 22% | 61% | 9% | 78% |
| A-argmax · panns10 | 100% | 25% | 75% | 0% |
| A · panns10 | 2% | 43% | 1% | 98% |
| C · panns10 + head | 22% | 83% | 4% | 78% |
| C-reg · panns10 + head (C=0.02) | 24% | 85% | 3% | 76% |
| C-agree · panns10 + head | 18% | 64% | 6% | 82% |
| A-argmax · yamnet | 100% | 40% | 60% | 0% |
| A · yamnet | 8% | 56% | 4% | 92% |
| C · yamnet + head | 25% | 82% | 4% | 75% |
| C-reg · yamnet + head (C=0.02) | 25% | 80% | 5% | 75% |
| C-agree · yamnet + head | 24% | 65% | 8% | 76% |

## Layered tracks on TEST (window thresholds from DEV)

| System | Window instrument P/R/F1 | Window family P/R/F1 | Events detected | Onset error median / p90 | Offset error median / p90 | Instrument F1 by #instruments |
|---|---|---|---|---|---|---|
| A · clap | 0.00/0.00/0.00 | 0.21/0.88/0.34 | 0/70 | – / – | – / – | 2: 0.00, 3: 0.00, 4: 0.00 |
| C · clap + head | 0.11/0.13/0.12 | 0.24/0.54/0.34 | 14/70 | 3.0 s / 5.0 s | 2.0 s / 6.0 s | 2: 0.12, 3: 0.09, 4: 0.15 |
| C-reg · clap + head (C=0.02) | 0.11/0.09/0.10 | 0.30/0.39/0.34 | 10/70 | 1.0 s / 4.2 s | 2.0 s / 5.1 s | 2: 0.02, 3: 0.08, 4: 0.15 |
| A · efficientat | 0.04/0.52/0.07 | 0.15/0.87/0.26 | 33/70 | 0.0 s / 1.5 s | 0.0 s / 1.5 s | 2: 0.06, 3: 0.07, 4: 0.07 |
| C · efficientat + head | 0.40/0.31/0.35 | 0.46/0.55/0.50 | 46/70 | 0.5 s / 7.0 s | 0.5 s / 2.8 s | 2: 0.35, 3: 0.33, 4: 0.37 |
| C-reg · efficientat + head (C=0.02) | 0.44/0.27/0.34 | 0.53/0.52/0.52 | 41/70 | 0.5 s / 4.0 s | 0.5 s / 7.5 s | 2: 0.33, 3: 0.36, 4: 0.32 |
| A · panns | 0.19/0.11/0.14 | 0.36/0.41/0.39 | 19/70 | 1.0 s / 12.0 s | 0.5 s / 12.1 s | 2: 0.14, 3: 0.17, 4: 0.12 |
| C · panns + head | 0.29/0.31/0.30 | 0.48/0.50/0.49 | 45/70 | 0.5 s / 7.8 s | 0.5 s / 10.4 s | 2: 0.33, 3: 0.30, 4: 0.26 |
| C-reg · panns + head (C=0.02) | 0.37/0.27/0.31 | 0.53/0.53/0.53 | 41/70 | 0.5 s / 8.0 s | 0.5 s / 12.0 s | 2: 0.37, 3: 0.31, 4: 0.26 |
| A · panns10 | 0.13/0.12/0.12 | 0.34/0.32/0.33 | 20/70 | 1.5 s / 11.9 s | 0.5 s / 12.1 s | 2: 0.12, 3: 0.15, 4: 0.11 |
| C · panns10 + head | 0.33/0.23/0.27 | 0.45/0.45/0.45 | 38/70 | 0.5 s / 8.9 s | 1.0 s / 9.2 s | 2: 0.34, 3: 0.19, 4: 0.29 |
| C-reg · panns10 + head (C=0.02) | 0.32/0.25/0.28 | 0.48/0.49/0.49 | 38/70 | 0.5 s / 8.7 s | 0.8 s / 9.2 s | 2: 0.33, 3: 0.27, 4: 0.25 |
| A · yamnet | 0.29/0.07/0.11 | 0.33/0.17/0.22 | 13/70 | 2.0 s / 11.9 s | 0.5 s / 11.2 s | 2: 0.15, 3: 0.13, 4: 0.07 |
| C · yamnet + head | 0.31/0.17/0.22 | 0.43/0.49/0.46 | 39/70 | 1.0 s / 12.2 s | 1.0 s / 8.9 s | 2: 0.23, 3: 0.23, 4: 0.21 |
| C-reg · yamnet + head (C=0.02) | 0.31/0.22/0.26 | 0.50/0.49/0.50 | 39/70 | 1.0 s / 5.2 s | 1.0 s / 12.1 s | 2: 0.28, 3: 0.24, 4: 0.25 |

## Source type on TEST (C heads; truth -> predicted)

- **C · clap + head**: acoustic -> acoustic: 74; acoustic -> electronic: 3; acoustic -> imitation: 46; electronic -> acoustic: 12; electronic -> electronic: 5; electronic -> imitation: 16; imitation -> acoustic: 25; imitation -> electronic: 1; imitation -> imitation: 34
- **C-reg · clap + head (C=0.02)**: acoustic -> acoustic: 114; acoustic -> imitation: 9; electronic -> acoustic: 29; electronic -> imitation: 4; imitation -> acoustic: 49; imitation -> imitation: 11
- **C · efficientat + head**: acoustic -> acoustic: 116; acoustic -> electronic: 1; acoustic -> imitation: 6; electronic -> acoustic: 4; electronic -> electronic: 26; electronic -> imitation: 3; imitation -> acoustic: 28; imitation -> electronic: 1; imitation -> imitation: 31
- **C-reg · efficientat + head (C=0.02)**: acoustic -> acoustic: 115; acoustic -> electronic: 1; acoustic -> imitation: 7; electronic -> acoustic: 5; electronic -> electronic: 26; electronic -> imitation: 2; imitation -> acoustic: 24; imitation -> electronic: 1; imitation -> imitation: 35
- **C · panns + head**: acoustic -> acoustic: 105; acoustic -> electronic: 4; acoustic -> imitation: 14; electronic -> acoustic: 2; electronic -> electronic: 24; electronic -> imitation: 7; imitation -> acoustic: 19; imitation -> electronic: 3; imitation -> imitation: 38
- **C-reg · panns + head (C=0.02)**: acoustic -> acoustic: 105; acoustic -> electronic: 4; acoustic -> imitation: 14; electronic -> acoustic: 4; electronic -> electronic: 24; electronic -> imitation: 5; imitation -> acoustic: 16; imitation -> electronic: 1; imitation -> imitation: 43
- **C · panns10 + head**: acoustic -> acoustic: 105; acoustic -> electronic: 6; acoustic -> imitation: 12; electronic -> acoustic: 5; electronic -> electronic: 27; electronic -> imitation: 1; imitation -> acoustic: 25; imitation -> electronic: 4; imitation -> imitation: 31
- **C-reg · panns10 + head (C=0.02)**: acoustic -> acoustic: 107; acoustic -> electronic: 4; acoustic -> imitation: 12; electronic -> acoustic: 3; electronic -> electronic: 28; electronic -> imitation: 2; imitation -> acoustic: 27; imitation -> electronic: 5; imitation -> imitation: 28
- **C · yamnet + head**: acoustic -> acoustic: 112; acoustic -> electronic: 2; acoustic -> imitation: 9; electronic -> acoustic: 7; electronic -> electronic: 23; electronic -> imitation: 3; imitation -> acoustic: 25; imitation -> electronic: 1; imitation -> imitation: 34
- **C-reg · yamnet + head (C=0.02)**: acoustic -> acoustic: 110; acoustic -> electronic: 1; acoustic -> imitation: 12; electronic -> acoustic: 7; electronic -> electronic: 21; electronic -> imitation: 5; imitation -> acoustic: 26; imitation -> electronic: 2; imitation -> imitation: 32

## DEV-selected head variant per model (C, C-reg, C-agree; chosen on DEV only)

| Model | Chosen | DEV coverage / wrong | TEST original cov / wrong / sel. family | TEST short cov / wrong | NSynth TEST cov / wrong |
|---|---|---|---|---|---|
| clap | C-agree | 16% / 5% | 25% / 16% / 36% | 6% / 3% | 6% / 4% |
| efficientat | C | 73% / 5% | 72% / 10% / 86% | 95% / 25% | 50% / 7% |
| panns | C-reg | 62% / 5% | 81% / 19% / 76% | 100% / 30% | 31% / 5% |
| panns10 | C-reg | 60% / 5% | 75% / 18% / 76% | 100% / 31% | 24% / 3% |
| yamnet | C | 56% / 5% | 55% / 11% / 80% | 56% / 19% | 25% / 4% |
