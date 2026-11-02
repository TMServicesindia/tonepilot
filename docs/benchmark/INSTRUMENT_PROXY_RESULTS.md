# Instrument recognition — first proxy benchmark results

**Status bucket: Tested on synthetic data only. NOT real Tamil/Telugu/Hindi accuracy.**
Run [41315008400](https://github.com/TMServicesindia/tonepilot/actions/runs/41315008400), 1 Nov 2026 (~21:15 IST).
Full tables: branch `ci/instrument-bench` (`bench/report.md`, `bench/report.json`).

**Setup.**
- Test: 64 instrument keys × 3 phrases, rendered from GeneralUser GS. Variants: original, reverb,
  compressed, 1 s. Plus 24 timed layered tracks.
- Training and threshold choice: the same keys rendered from FluidR3 GM (MIT), which is a different
  sample set.
- **A** = each model's own labels mapped to the taxonomy; **C** = frozen embeddings + small logistic
  head trained on FluidR3 renders only.
- 1 s windows, 0.5 s hop.

## Headline (solo clips, original)

| System | Exact | Family | Wrong family | Unknown |
|---|---|---|---|---|
| A · Apple SoundAnalysis (today's app) | 2% | 5% | 1% | 94% |
| A · YAMNet | 0% | 10% | 4% | 86% |
| A · PANNs | 0% | 19% | 8% | 73% |
| A · EfficientAT | 2% | 11% | 89% | 0% |
| A · CLAP (zero-shot) | 0% | 0% | 0% | 100% † |
| **C · EfficientAT + head** | **59%** | 75% | 25% | 0% |
| C · PANNs + head | 55% | **77%** | 23% | 0% |
| C · YAMNet + head | 54% | 73% | 27% | 0% |
| C · CLAP + head | 28% | 41% | 59% | 0% † |

Layered tracks (overlapping instruments, timed). EfficientAT + head is best:
- **window** instrument F1 0.37, family F1 0.53;
- **track** instrument F1 0.48;
- median start+end error 3.0 s.

Robustness, EfficientAT + head, family (exact):
- original 75% (59%);
- reverb 80% (59%);
- compressed 74% (54%);
- 1 s clips 73% (53%).

TonePilot's imitation tones (bansuri-like etc.), family accuracy: 53% (EfficientAT), 61% (PANNs).

## Size and speed (CI CPU; iPhone not yet measured)

| Model | Parameters | Seconds per audio minute | Core ML |
|---|---|---|---|
| EfficientAT mn10 | 4.9 M | **0.28** | **9.9 MB fp16, 4.5 ms per 1 s window** (Mac runner; matches PyTorch) |
| YAMNet | ~3.7 M | 0.61 | not converted yet |
| Apple SoundAnalysis | built into iOS | 0.97 (Mac runner) | — |
| PANNs Cnn14 | 81.8 M | 4.93 | too large for default |
| CLAP (audio branch) | 68.6 M | 23.7 | too large for default |

## What this shows, and what it doesn't

1. **Off-the-shelf labels (A) are not usable for TonePilot's taxonomy**, including today's Apple
   classifier. They mostly abstain (Apple 94% unknown) or answer the wrong family (EfficientAT 89%).
2. **Embeddings + a small TonePilot head (C) are far better** on unseen sample sets: 54–59% exact,
   73–77% family, without any fine-tuning.
3. **EfficientAT + head leads overall.** It is best on exact and on layered recognition, very close to
   PANNs on family, about 18× faster and 17× smaller than PANNs, and ~10 MB as Core ML (iPhone).
   It is the leading candidate, **not yet the chosen one**.
4. **Still too many confident wrong answers** (C: ~25% wrong family, 0% unknown). The thresholds are
   tuned for coverage, not caution. Next: calibrate abstention so a wrong family is rare and
   uncertainty becomes "unknown", and report coverage alongside.
5. **Layered detection is weak** (window F1 0.37). The head was trained on few layered examples.
   More training mixtures are needed; a multi-instance training trick may help.
6. **† CLAP is under-measured here.** 1 s windows are far shorter than its 10 s training clips, and
   softmax over ~75 instrument prompts makes my zero-shot threshold always abstain. A fair CLAP test
   needs longer windows and an argmax variant. Given its size (68.6 M parameters, 24 s per audio
   minute on CPU), it stays an optional benchmark, as the owner decided.
7. **Synthetic only.** Same instrument names, General MIDI-style samples, no real Indian
   instruments. **Tabla, mridangam, dholak, ghatam, kanjira, thavil, dhol and viola have no licensed
   audio at all.** Nothing here measures film-music accuracy.

## Next steps (approved scope: research and proxy benchmarking)

1. Calibrated abstention (target: wrong-family ≤ 5% on DEV) + coverage reporting.
2. More layered training mixtures; window-level multi-label training.
3. Add NSynth (real sampled instruments, acoustic/electronic/synthetic labels).
4. Fair CLAP run (longer windows, argmax).
5. Licensed real recordings (Freesound/Commons CC0/CC BY per file, GuitarSet, Saraga after the
   licence check), especially the Indian instruments.
6. Mel front-end in Swift + Core ML model behind `InferenceBackend`, for **shadow-mode** measurements
   on iPhone. This needs owner approval before anything appears in the app.


---

## Gate 1 v2 — calibrated abstention with a cross-domain DEV (run 41321917030, calibration run 41324196558)

DEV = FluidR3 held-out phrase 2 + layered 77–95 **+ NSynth-valid** (real notes, a different source).
TEST = GeneralUser GS (untouched) and NSynth-test (separate). Heads trained on FluidR3 TRAIN only.
96 layered training mixtures.

**EfficientAT + head on TEST** (coverage / wrong family / selective family accuracy):

| Condition | Coverage | Wrong family | Selective family acc. |
|---|---|---|---|
| Clean | 41% | 3% | 94% (selective exact 82%) |
| Reverb | 43% | 3% | 94% |
| Compressed | 27% | 3% | 90% |
| Short 1 s | 81% | **25%** | 69% |
| Imitation tones | 27% | 14% | 49% |

- **Target ≤ 5% wrong family is now met on untouched TEST** for clean, reverb and compressed clips.
  This is the trade-off: 41% coverage. **It fails on short clips**: DEV had none, so thresholds don't cover them.
- PANNs + head: 41% / 5% / 87%. YAMNet + head: 63% / 12% / 81%.
- **NSynth-test (real notes): every head generalises poorly.** EfficientAT + head answers 11% of clips at 33%
  selective accuracy. **Training only on General MIDI renders does not transfer to real instruments.**
  Next: add NSynth-*train* (CC BY 4.0, separate instruments) to TRAIN.
- Layered (EfficientAT + head): window instrument F1 0.39, family F1 0.58, events detected 57/75,
  onset error median 0.5 s / p90 7.7 s. Little change from 4× more mixtures.
- Source type: imitation tones still mostly classified as acoustic (9/36 right).
- CLAP with 10 s windows: still poor (head 0% coverage on clean). It stays optional, as decided.


---

## Gate 1 v3 — NSynth-train (real notes, CC BY 4.0) added to TRAIN (bench run 41325343802, calibration run 41327588521)

EfficientAT + head (coverage / wrong family / selective family accuracy):

| TEST set | v2 (GM-only training) | **v3 (+ NSynth training notes)** |
|---|---|---|
| NSynth-test (real notes, different instruments) | 11% / 8% / 33% | **47% / 6% / 87%** |
| GeneralUser (synthetic), clean | 41% / 3% / 94% | 78% / **17%** / 78% |
| GeneralUser, 1 s clips | 81% / 25% / 69% | 96% / 36% / 62% |

YAMNet + head v3:
- GeneralUser: 62% / 9% / 85%;
- NSynth: 25% / 5% / 78%.

Findings:
1. **Real recorded training notes transform real-instrument generalisation**: 33% → 87% selective
   accuracy on unseen real NSynth instruments. Licensed real recordings are the lever.
2. **One threshold does not fit two sound domains.** Calibrated on a mixed DEV (FluidR3 + NSynth), it
   became too lenient for the synthetic set.
3. Calibration must therefore come from DEV audio that resembles the target (real film music); until
   that exists, per-condition thresholds (duration-aware, added in v4) are the principled interim step.
4. Layered (v3): window instrument F1 0.37, family F1 0.55, onset error median 0.5 s / p90 6.4 s.

---

## Gate 1 v4 — synthesised Indian imitations + duration-aware thresholds (bench run 41328362434, calibration run 41331398996)

All SYNTHETIC proxy (GM sound banks and in-house imitation synths). Not film-music accuracy.

What changed:
- Synthesised "imitation" tones (bansuri, violin, cello, nadaswaram, shehnai, sitar, veena, santoor) were added to every split.
- Clips of 1 s and under got their own DEV-calibrated thresholds.
- PANNs was included; CLAP finished too late for this calibration.

EfficientAT + head (coverage / wrong family / selective family accuracy), measured on TEST (GeneralUser GS, untouched):

| TEST set | v3 | **v4** |
|---|---|---|
| GeneralUser, clean | 78% / 17% / 78% | **72% / 10% / 86%** |
| GeneralUser, 1 s clips | 96% / 36% / 62% | 95% / 25% / 73% |
| Imitation tones | 74% / 49% / 33% | **78% / 22% / 72%** |
| NSynth-test (real notes) | 47% / 6% / 87% | 50% / 7% / 87% |

Other heads on GeneralUser, clean:
- PANNs + head: 85% / 26% / 70%
- YAMNet + head: 55% / 11% / 80%

The EfficientAT lead holds (on NSynth: EfficientAT 87% selective at 50% coverage; PANNs 79% at 25%; YAMNet 82% at 25%).

Findings:
1. **Imitation tones in training help the family decision a lot**: imitation wrong-family went from 49% to 22%, and the clean set's wrong-family went from 17% to 10%.
2. **Source type (CORRECTED 2 Nov).** An earlier version said the head never answers "imitation" (28/28 → acoustic). That was wrong: it came from a log line cut at 250 characters. The full v4 result for EfficientAT + head C on the 60 TEST imitation clips:
   - 31 classified as imitation;
   - 28 as acoustic;
   - 1 as electronic.

   About half of imitations are recognised, so the distinction is weak, not absent. Real acoustic/imitation pairs are still the lever.
3. **Short-clip thresholds did not reach the target on DEV.** The head is confidently wrong on single 1 s windows: even at a 0.99 threshold, DEV wrong-family stays above 5%. Thresholds alone cannot fix this. The v4b calibration run tests a stronger-regularised head and a "heads must agree" rule, selected on DEV only.
4. Layered mixtures (EfficientAT + head):
   - window instrument F1 0.34, family F1 0.50;
   - 46/70 events detected;
   - onset error median 0.5 s, p90 7.0 s.
   - Little change from v3.
5. The Apple SoundAnalysis job crashed again near the end of NSynth (about 4,200 of 4,356 clips). A per-clip autorelease-pool fix is committed and will be checked on the next bench run.
6. CLAP (10 s windows, bench evaluate job; finished after the calibration run):
   - head: 3% coverage on clean (57% selective);
   - argmax: 93% wrong family.
   - CLAP stays optional and is not pursued further, as decided.

### v4b — head variants for confidently-wrong answers (calibration run 41333007005, same bench run)

This run tests three variants of each head (SYNTHETIC proxy):
- **C**: as before.
- **C-reg**: stronger regularisation (C=0.02, unweighted).
- **C-agree**: answer only when the instrument head's best guess belongs to the family head's best family.

The variant is chosen on DEV only.

EfficientAT (coverage / wrong family / selective family accuracy), measured on TEST:

| Variant | DEV cov / wrong | GeneralUser clean | GeneralUser 1 s clips | Imitation tones | NSynth-test (real notes) |
|---|---|---|---|---|---|
| **C (DEV-selected)** | 73% / 5% | 72% / 10% / 86% | 95% / 25% / 73% | 78% / 22% / 72% | **50% / 7% / 87%** |
| C-reg | 72% / 5% | 76% / 12% / 84% | 100% / 29% / 71% | 76% / 23% / 70% | 46% / 4% / 90% |
| C-agree | 55% / 5% | **70% / 6% / 91%** | **60% / 7% / 88%** | 64% / 12% / 82% | 24% / 9% / 61% |

Findings:
1. **C-agree fixes the short-clip problem on the synthetic sets**: 1 s clips go from 25% to 7% wrong-family. It is also the only EfficientAT variant whose short-clip thresholds reach the 5% target on DEV.
2. **But C-agree is worse on real NSynth notes**: wrong-family rises from 7% to 9% and selective accuracy falls from 87% to 61%. It also has lower DEV coverage, so the agreed DEV rule (highest DEV coverage at ≤5% wrong) still selects plain C. **The official result stays C.**
3. A stricter DEV rule, "meet the target on DEV overall and on DEV short clips", would pick C-agree. That rule was thought of *after* seeing TEST, so it is not adopted here. It needs confirming on data not yet looked at; the first real annotated DEV/TEST set is the right place.
4. Stronger regularisation (C-reg) changes little. Overconfidence comes from the domain gap between sound banks, not overfitting within one.
5. No variant reaches ≤5% wrong-family on every TEST condition. The remaining lever is the same as v3 concluded: **licensed real recordings** for training, DEV and TEST.

---

## E2: PANNs CNN10 challenger (run 41386940981, commit 9bf59ce; reuses bench run 41328362434)

Pre-declared protocol (`docs/TONEPILOT_INSTRUMENT_ACCURACY_ROADMAP.md`):
- same clips, splits, 1 s windows and heads for every encoder;
- DEV selects; TEST is reported once.

Everything here is SYNTHETIC proxy + NSynth, not film-music accuracy.

**CNN10 facts:**
- weights from Zenodo 3987831, SHA-256 `5240bdc47444e331bbeb54fd741d2b3f933a4526e84b0c17bf3593df94b13962`;
- all weights loaded, 0 unexpected keys;
- 6.30 M parameters as counted, including the frozen spectrogram front-end (5.2 M published);
- 2.0 s CPU per audio minute, against EfficientAT 0.44 s (EfficientAT is 4.5× faster on CI CPU);
- licence: code MIT, weights CC BY 4.0.

**Primary metric (DEV coverage at wrong-family ≤ 5%), with TEST shown for reference:**

| Encoder (DEV-selected variant) | DEV coverage | TEST clean (cov / wrong / selective) | TEST 1 s | NSynth-test (cov / wrong / selective) | Layered window F1 (instrument / family) | Onset error median / p90 |
|---|---|---|---|---|---|---|
| **EfficientAT (C), official** | **73%** | 72% / 10% / 86% | 95% / 25% | **50% / 7% / 87%** | **0.35 / 0.50** | 0.5 s / 7.0 s |
| PANNs CNN10 (C-reg) | 60% | 75% / 18% / 76% | 100% / 31% | 24% / 3% / 85% | 0.28 / 0.49 | 0.5 s / 8.7 s |
| PANNs CNN14 (C-reg) | 62% | 81% / 19% / 76% | 100% / 30% | 31% / 5% / 85% | 0.31 / 0.53 | 0.5 s / 8.0 s |
| YAMNet (C) | 56% | 55% / 11% / 80% | 56% / 19% | 25% / 4% | 0.22 / 0.46 | 1.0 s / 12.2 s |

**Plain C head, all encoders, TEST clean:**
- CNN10: 59% / 9% / 85%;
- EfficientAT: 72% / 10% / 86%.

**Coverage curve (TEST clean; family accuracy of the most confident share):**

| Encoder | 70% | 50% | 30% |
|---|---|---|---|
| EfficientAT C | 82% | 87% | 94% |
| CNN10 C | 81% | 86% | 91% |

**Source type (TEST, C heads; imitation clips n = 60):**
- EfficientAT: 31 imitation / 28 acoustic / 1 electronic;
- CNN10: 31 imitation / 25 acoustic / 4 electronic;
- CNN14: 38 / 19 / 3.

**Decision under the pre-declared rule: CNN10 does not replace C.**
- It loses the primary metric: DEV coverage 60% against 73%.
- It loses two guards:
  - NSynth coverage 24% against 50% (lower wrong-family, 3% against 7%, but at half the coverage);
  - layered instrument F1 0.28 against 0.35.
- On TEST it does not beat C on the clean or short sets, and it is 4.5× slower on CPU.
- **EfficientAT + head C stays the official candidate.**

What E2 does not show:
- whether the ranking holds on real Indian audio (E1, Sanidha, pending access);
- anything about iPhone performance.

Short clips remain a shared weakness (every DEV-selected encoder has wrong-family ≥ 19% on 1 s TEST clips), and so does the 5% wrong-family target on TEST.

---

## Tone recreation: where the main-tone matcher fails (2 Nov; core bench, Docker, release build)

Bench: `ToneMatchingBenchmarks`. 12 rendered songs (lead + backing + voice + bass, 20% leakage between stems); candidates are TonePilot's own tones (GeneralUser GS).

Splits:
- **DEV:** same bank (GeneralUser) and cross-bank (TimGM6mb).
- **Sealed TEST:** cross-bank FluidR3 GM, run **once** for the old and once for the new code.

"Exact" = same GM program; "family" = same instrument family.

**Diagnosis:**
1. With clean audio and the whole library, the fingerprint ranks the true sound **1st in 10/12 and 2nd in 2/12** (same bank).
2. But the tag-based pre-selection (14 candidates; whole families such as piano excluded for leads) **dropped the true sound in 8/12**.
3. Note extraction is not the bottleneck: extracted notes are mostly on pitch, and true notes give the same cross-bank result.
4. **Across sound sources the hand-crafted fingerprint does not recognise the instrument.** A different bank's flute or violin scores closer to our brass, worse with backing leakage. A harmonic-profile feature was tried and did not help (removed).

| Matcher | Same bank (lead exact / family; backing exact / family) | Cross-bank DEV TimGM6mb | **Sealed TEST FluidR3** | Time (12 songs) |
|---|---|---|---|---|
| Current (shipping) | 4/7; 2/5 | 2/3; 0/1 | **0/3; 0/1** | 185 s |
| Two-stage whole-library screen (branch `research/tone-shortlist`) | **8/9; 2/7** | 2/2; 0/1 | **1/2; 1/2** | 398 s |

**Decision: not shipped.**
- It wins only when the song's exact sample is in our library, which is never the case for real songs.
- On the sealed TEST it is no better than the current matcher, and it is 2× slower.

**Measured conclusion:** recognisable tones on real songs need **cross-source instrument identity**. On its own cross-bank TEST (trained on FluidR3, tested on unseen GeneralUser), the gated EfficientAT + head C reached **86% selective family accuracy at 72% coverage**, against about 17–25% top-1 family for the fingerprint on cross-bank audio. The next step is to let a confident family decision from C gate the tone search, with the fingerprint choosing only within that family. That requires an owner decision on shipping the research model before its gates (G2.4 device run; ≤ 5% wrong-family not yet met).

---

## Tone E-4: nearest tone by embedding similarity (run 41406558483; DEV banks only; rendered GM audio, not real songs)

Method:
- the TonePilot library (130 tones × 3 registers, rendered by TonePilot's engine) is compared with each target part (bench lead/backing stems with leakage) by cosine similarity, best register;
- truth = GM program (exact) / TonePilot family.

| Method | Same bank lead (exact / family / top-3 family) | Same bank backing | **Cross-bank TimGM lead** | **Cross-bank TimGM backing** |
|---|---|---|---|---|
| Shipping fingerprint (bench, 2 Nov; full PartMatcher path) | 4 / 7 / — | 2 / 5 / — | 2 / 3 / — | 0 / 1 / — |
| MFCC (hand features) | 0 / 1 / 2 | 9 / 11 / 12 | 0 / 0 / 0 | 1 / 1 / 1 |
| **EfficientAT embedding** | **6 / 9 / 9** | 3 / 8 / 9 | **3 / 5 / 5** | **2 / 6 / 6** |
| PANNs CNN10 embedding | 5 / 7 / 9 | 4 / 6 / 10 | 2 / 5 / 7 | 2 / 2 / 7 |

Embedding time for all 438 clips (CI CPU): EfficientAT 25 s, CNN10 113 s.

**Local follow-up (MFCC, same harness):** harmonic-only part isolation (+harm: STFT mask at the notes' harmonics) raises same-bank lead from 0/1 to **6/7 exact/family**, confirming the leaking backing hurts whole-clip descriptors. LDA on FluidR3 renders did not help MFCC.

**Next (E-5, run 41407645614):** EfficientAT with +harm, +lda (FluidR3 training renders) and both.
