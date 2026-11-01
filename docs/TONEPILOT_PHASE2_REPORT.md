# TonePilot — Phase 2 (Rhythm) Report

**Date:** 1 November 2026 (IST) · **Owner instruction:** "Continue with other phases also. One by one slowly."
**Status: implementation and measurement done; adoption blocked.** One acceptance gate failed (Beat This!
does not improve on the current tracker), and real-audio acceptance cannot run (0 Indian clips).
Nothing from Phase 2 is wired into the app's analysis, so there is **no user-visible change**.

## 1. What was built

| Step | What | Result |
|---|---|---|
| 1 | `beat-this-convert.yml`: Beat This! `small0` (CPJKU, MIT; sha256 `6074be2c…`) → Core ML, checked against PyTorch | **PASS**: max \|diff\| 1.9e-5 (gate 1e-3), identical beat peaks on CPU and on all compute units |
| 2 | Swift front-end, chunking and post-processing (`Rhythm/BeatThis.swift`) | **Identical to the official code**: log-mel within 6.4e-5; beat/downbeat times exact; chunk aggregation exact |
| 3 | `RhythmCycleInference` (`Rhythm/RhythmCycle.swift`): cycle length + start with **confident / ambiguous / unknown**; never forces a Western label | 7 unit tests pass |
| 4 | Rhythm benchmark (`RhythmBenchmarks`, `bench.yml` macOS job): 36 rendered songs, 6 cycles (6/8, 3/4, 4/4, khanda chapu 5, misra chapu 7, adi 8) × 72/96/128 BPM × with/without drums | §2 |

How the cycle decision works:
- Model downbeats (when present) are scored by F-measure.
- Accents (bass energy + chord change at each beat) must make the cycle start stand out from **every** other position.
- Without a model, the longest such cycle is chosen. It is confident only if double and half the length clearly fail.
- Any disagreement between model and accents (including a multiple such as 8 vs 4) blocks confidence.

## 2. Results (synthetic S1; CI run 41298094789)

| Method | Cycle right | Wrong but confident | Confident / ambiguous / unknown | Beat F |
|---|---|---|---|---|
| Current analyzer metre (today's app) | 6/36 | **30 (83%)** | 36 / 0 / 0 | 0.82 |
| **Cycle inference on current beats + accents** | **31/36** | **0 (0%)** | 17 / 19 / 0 | 0.82 |
| Beat This! + cycle inference | 12/36 | 1 (3%) | 4 / 30 / 2 | 0.80 |

Beat F by condition: without drums, current 0.82 vs Beat This! 0.75; with drums, 0.83 vs 0.84.
Beat This! speed: **16–18 s per 4-min song** (macOS CI runner, Core ML). The target is ≤ 10 s added per
song on iPhone 15; it has not been measured on a phone.

Findings:
1. **Beat This! downbeats follow Western bars:** adi read as 4, khanda/misra chapu as 2. This was the
   risk the plan named ("Western-trained rhythm models on Indian cycles").
2. Beat This! is not better than the current beat tracker on this set and is worse without drums.
3. The separate cycle stage is the real gain: 6/36 → 31/36 with zero confident errors, using only
   the current beats.
4. Remaining errors are honest "ambiguous" answers: 6/8 at the wrong beat level, and misra chapu read as 14.

## 3. Acceptance gates

| Gate (roadmap Phase 2) | Status |
|---|---|
| Core ML numerically equal to PyTorch | **PASS** |
| Beat/cycle targets on S1 | Cycle stage: 31/36, 0% wrong-confident (target ≤ 5%) **PASS**; Beat This! **FAIL** (no improvement) |
| Improvement on S6 (real Indian) | **Cannot run: 0 clips** |
| Wrong confident cycle labels ≤ 5% | Cycle stage 0%, Beat This! path 3%: **PASS** |
| ≤ 10 s added per 4-min song on iPhone 15 | Beat This!: 16–18 s on the CI Mac; **not measured on iPhone** |
| Both platforms equal | **Not done** (Android LiteRT deferred) |

**Decision under your rules:** Beat This! is **not adopted** (it does not improve on the current
implementation). The cycle stage is ready but stays **off** until it passes on real Indian audio.
The gate is not weakened.

## 4. Files changed in Phase 2

- `Packages/TonePilotCore/Sources/TonePilotCore/Rhythm/BeatThis.swift`, `Rhythm/RhythmCycle.swift` (new)
- `Packages/TonePilotCore/Sources/TonePilotCore/Inference/CoreMLBackend.swift` (moved from `App/Sources/Audio/`, unchanged logic)
- `Tests/.../BeatThisTests.swift`, `RhythmCycleTests.swift`, `Benchmarks/RhythmBenchmarks.swift`, `Fixtures/rhythm/beat_this/*` (new)
- `.github/workflows/beat-this-convert.yml`, `Native/tools/beat_this/convert_beat_this.py` (new); `bench.yml` (macOS rhythm job); `ios-build.yml` (contract step uses core's Core ML back-end)
- `docs/LICENSES/manifest.json` (Beat This! checkpoint hash and source commit)

## 5. What is needed to finish Phase 2

1. **Indian clips** (`docs/benchmark/indian-set/`): the cycle stage must show improvement there before it is switched on.
2. Your decision: switch the cycle stage on (behind a setting) once it passes on real clips, or wait.
3. Android parity (LiteRT) — still deferred for the iPhone priority.
