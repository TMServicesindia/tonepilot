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
