# TonePilot — Recommended Architecture (revision 3)

**Date:** 1 November 2026 · **Status:** for the owner's approval; nothing implemented. Revision 3 applies the owner's final review:
- Android parity starts in Phase 1.
- Model outputs are evidence, not decisions.
- Bass notes are root evidence, not roots.
- Transcription is optional per stem.
- False arpeggios get a separate zero gate.
- Pattern validation checks the actual notes, not only the sound.
- Stop behaviours are compared.
- Real Indian audio is mandatory.
- SAFE\* is never unconditional clearance.
- Existing features are protected.

**Product core:** TonePilot is a *song-aware accompaniment reconstruction system*. It listens to a song, understands its accompaniment, extracts the actual pattern, and lets the player recreate it by playing simple chords on the Casio CT-X870IN. The Song Arpeggio chain (rhythm → harmony → note events → accompaniment type → pattern → live fill) gets most of the effort. Instrument recognition and tone matching come later and stay separate.

## Evidence labels (used throughout)

| Label | Meaning |
|---|---|
| **Measured** | Run on 1 Nov 2026 with the audit harness (synthetic songs rendered from GeneralUser GS; real audio not yet measured) |
| **Target** | An acceptance threshold proposed for approval; not yet achieved |
| **Estimate** | Engineering judgement |
| **Unknown** | Not established; the phase that will establish it is named |

---

## 1. Principles

1. **Accuracy before model count.** A model is adopted only when it beats the current code on independent **real** audio, including the Indian acceptance set.
2. **Evidence, not verdicts.** A neural model contributes evidence with confidence. Final musical decisions (cycle, chord, accompaniment type, pattern) are made in TonePilotCore, and can always answer "unknown".
3. **Shared core, two inference back-ends, from Phase 1.** All pre-processing, post-processing and decision logic live in TonePilotCore. Inference runs behind one `InferenceBackend` interface: Core ML on iOS; LiteRT (TFLite) or ONNX Runtime on Android. **No model is approved without a working Android back-end.**
4. **Separate stages, separate tests:** note transcription, harmony, rhythm, accompaniment type, pattern learning, recognition and tone matching.
5. **Protected functionality.** These stay unchanged and regression-tested unless a separately approved change says otherwise:
    - Melody Player (melody guide)
    - ToneEngine
    - NoteRouter and MIDI
    - normal keyboard playing
    - Record
    - Song Studio
    - Tone Studio
6. **Commercial builds** contain only models, weights, dependencies and data whose licence records are complete and reviewed (`TONEPILOT_LICENSING_CHECKLIST.md`). Personal builds may keep the current Demucs.

## 2. Data flow

```
Import (audio the user has rights to)
 │
 ├─ Decode, first analysis (existing)
 ├─ Separation (existing Demucs in personal builds; commercial builds: cleared weights only, §4)
 │      vocals · drums · bass · other (+ piano · guitar) → Lead / Backing (existing DSP)
 │
 ├─ R1 BEAT EVIDENCE   Beat This! small → beat/downbeat activations   (model, evidence only)
 │                     TempoAnalyzer → tempo + onset periodicity       (existing DSP)
 │                     onset subdivision (2/3/4 per beat) from stems   (DSP)
 │
 ├─ R2 CYCLE INFERENCE (separate stage, own code)
 │      accent periodicity over beats + downbeat evidence + chord-change timing + repetition
 │      → RhythmCycle {beats per cycle, subdivision, accent groups (3+2+2, 4+4…),
 │                     confidence, state: confident | ambiguous | unknown}
 │      Western label only when confident and conventional; never forced
 │
 ├─ H  HARMONY (hypotheses, not a single forced answer)
 │      evidence: bass pitch (root evidence), bass-free chroma, key context, temporal smoothing,
 │                optional BTC chord posteriors (model, evidence only)
 │      → per beat: best chord + ranked alternatives + confidence; states: chord | drone/modal | no-chord
 │
 ├─ N  NOTE EVENTS per accompaniment stem
 │      existing DSP probe (always) ⊕ Basic Pitch (only for stem types where it measured better)
 │      → onset, offset, pitch, velocity, confidence
 │
 ├─ A  ACCOMPANIMENT TYPE per section (rules + features; conservative)
 │      broken-chord · rhythmic chord · sustained · hook/phrase · bass-only · none · uncertain
 │      live fill allowed only for broken-chord / rhythmic chord with high confidence
 │
 ├─ P  PATTERN LEARNING (existing ArpeggioLearner, extended; combines R2 + H + N + A)
 │      actual note order, timing, duration, register, accents → chord-relative events
 │      main pattern + per-bar variations + per-event confidence
 │      validation: objective note-event checks + owner listening (both required)
 │
 ├─ L  LIVE FILL (existing LiveArpeggiator + LiveFill, rules tightened)
 │
 └─ T  INSTRUMENTS AND TONES (later, separate): recognition vs matching
```

## 3. Change register

Fields per change: current · proposed · why · licence (record status, see checklist) · expected benefit · size and device · benchmark and acceptance · fallback.

### C1 — Beat evidence

| Field | Content |
|---|---|
| Current | `TempoAnalyzer`: onset autocorrelation + Ellis DP beats |
| Proposed | Beat This! small supplies beat and downbeat **activations as evidence**; TempoAnalyzer supplies tempo and periodicity; a fusion step in TonePilotCore produces the beat grid and passes downbeat evidence to C2. Beat This! never decides the cycle on its own |
| Why | **Measured:** beat F 0.52 without drums, 0.92 with; 6/24 tempo errors (half/double/×1.5) |
| Licence | Code and weights MIT (README). Training data includes copyrighted / limited-CC files (README). **SAFE\*: model record complete; data provenance needs review before a commercial release** |
| Expected benefit | **Unknown** until Phase 2 measures it. **Target:** no-drum beat F ≥ 0.85 on synthetic data, and better than TempoAnalyzer on the real Indian set |
| Size / device | ~8.1 MB (README). Inference time and memory: **unknown** (Phase 2, iPhone 15 and one mid-range Android) |
| Benchmark / acceptance | Beat F, downbeat F, CMLt/AMLt on S1, S2 and the mandatory real Indian set (S6); improvement required on S6 |
| Fallback | TempoAnalyzer only (feature flag) |

### C2 — Rhythmic cycle inference (separate stage)

| Field | Content |
|---|---|
| Current | Two heuristics (`SectionInsights.timeSignature`, `ArpeggioLearner.downbeatPhase`). **Measured:** 10/24 |
| Proposed | `RhythmCycle` stage in the core. Evidence: accent periodicity, Beat This! downbeats, chord-change timing, bar repetition, subdivision. Output: beats per cycle (2–16), subdivision (2/3/4), accent groups, confidence, and a state of confident, ambiguous or unknown. Patterns and live fill use the cycle; the UI shows "7-beat cycle (3+2+2)", "6/8", or "cycle unclear" |
| Why | A beat/downbeat model doesn't identify tala or Indian rhythmic cycles. A forced label creates wrong pattern lengths |
| Licence | Own code |
| Expected benefit | **Target:** cycle length ≥ 85%, subdivision ≥ 90% on S1 + S6; on rubato, ≥ 80% of clips reported as ambiguous or unknown, not a wrong label |
| Size / device | 0 MB; shared core |
| Benchmark / acceptance | S1 rhythm set, S6 Indian cycles (mandatory), S5 rubato/tempo change; wrong confident labels reported separately (target: ≤ 5%) |
| Fallback | Current heuristics, shown as "unclear" when they disagree with downbeat evidence |

### C3 — Harmony with hypotheses

| Field | Content |
|---|---|
| Current | `HarmonyAnalyzer`: KK key profiles, 24 triad templates, beat-level Viterbi on full-mix chroma. **Measured:** 70% of bars; minor keys 25–44%; sevenths/inversions 75% |
| Proposed | Per beat, combine (a) bass pitch as root **evidence** (inversions and pedal bass allowed), (b) bass-free chroma from backing/other, (c) key context, major and minor, with relative-key ambiguity, (d) temporal smoothing, (e) optional BTC posteriors. Output the best chord, ranked alternatives and a confidence. States: chord, drone/modal (no triad forced) or no-chord. Changes allowed on any beat |
| Why | A wrong chord makes the fill play a wrong third. Bass notes are not always roots |
| Licence | Own DSP. BTC: MIT repository with model files (SAFE\*; data: Isophonics, Robbie Williams, UsPop annotations; audio collected by the authors) |
| Expected benefit | **Target:** ≥ 85% beat-level accuracy, minor keys ≥ 75%, half-bar changes found; drone passages labelled drone ≥ 90% (S1) |
| Size / device | 0 MB DSP; BTC 12.2 MB, conversion **unknown** |
| Benchmark / acceptance | S1 chord set (minor keys, 7ths, inversions, slash chords, half-bar changes, drones), S2, S4/S6 real audio; BTC adopted only if it beats improved DSP on real audio |
| Fallback | Current analyzer; low-confidence chords feed the live-fill third rule (C7) |

### C4 — Note events (transcription as an optional experiment)

| Field | Content |
|---|---|
| Current | ArpeggioLearner onset envelope + harmonic-sum probe |
| Proposed | The existing probe always runs. Basic Pitch runs as an experiment per stem type (piano, guitar, strings, synth, mixed backing). It is enabled only for stem types where it measurably improves note-event F; otherwise the DSP probe wins. ByteDance piano and YourMT3 run only offline as reference upper bounds |
| Why | Dense strings, piano and orchestral backing are hard for any transcriber |
| Licence | Basic Pitch Apache-2.0 (repo, official HF card, LiteRT card). SAFE\*: training-data list to record. **Not a required dependency** |
| Expected benefit | **Unknown** per stem type until Phase 4 |
| Size / device | 0.84 MB LiteRT (Android benchmarks on its card); iPhone Core ML **unknown** |
| Benchmark / acceptance | Note F (onset ±50 ms), offset F, octave-error rate, per stem type on GuitarSet, Slakh, S1, S3 and S6 |
| Fallback | DSP probe |

### C5 — Accompaniment type (conservative)

| Field | Content |
|---|---|
| Current | Pattern or "sustained" |
| Proposed | Classes: broken-chord, rhythmic chord, sustained, hook/phrase, bass-only, none, uncertain. Decision rule: **live fill only for broken-chord or rhythmic chord with confidence above a strict threshold; everything else defaults to no fill.** Features: polyphony per onset, cross-bar repetition, chord-tone ratio, step-wise motion, onset density |
| Why | A violin hook or flute solo must never become an arpeggio |
| Licence | Own |
| Expected benefit | **Target (primary): false-arpeggio rate = 0** in hook, solo, sparse and sustained sections across S1, S4, S5 and S6. Secondary: overall type accuracy ≥ 85%, reported separately. Missed arpeggios (fill suppressed where allowed) are reported but secondary |
| Size / device | 0 MB |
| Benchmark / acceptance | Labelled sections; confusion matrix published; the false-positive rate is gated separately from accuracy |
| Fallback | No fill (safe default) |

### C6 — Pattern learning that preserves the song

| Field | Content |
|---|---|
| Current | `ArpeggioPattern` steps × degrees, velocity and length. **Measured:** 100% degrees and step F 1.00 **with true beats and chords** |
| Proposed | Learn from note events on the cycle grid with chord hypotheses. Each event keeps cycle position, chord degree, octave offset, duration, accent and register. The original note order is kept exactly (e.g. Root → Fifth → Octave → Third → Fifth → Octave). Bars are clustered into a main pattern plus variations, with per-event confidence |
| Validation | **Both are required:** (1) objective checks against the reference (note order, onset timing, duration, register, chord degree, variation placement); (2) owner listening with A/B against the original stem. Passing one without the other fails |
| Why | An A/B can sound convincing while the sequence is wrong |
| Licence | Own |
| Expected benefit | **Target:** degree accuracy ≥ 90% and onset error ≤ 30 ms median with **estimated** beats and chords (S1); variation placement ≥ 80% (S1); owner approval on 10 real sections from S3/S6 |
| Size / device | 0 MB |
| Benchmark / acceptance | Per-event metrics + edit distance per bar (median ≤ 1) + listening sheet |
| Fallback | Current learner output, marked "approximate" |

### C7 — Live fill

| Field | Content |
|---|---|
| Current | Fill after R·5; melody above the split ignored; full chord silent; chord memory; MIDI-thread processing with separate locks; continues to the chord's end |
| Proposed | (1) **Third rule:** play a third only if the player played it, memory holds it, or the song chord's confidence is above the threshold; else root-fifth-octave voicings. (2) **Stop behaviour benchmarked:** immediate stop on release, stop after one silent cycle, and a configurable option (setting with a sensible default chosen from the test). (3) Validated patterns for allowed accompaniment types only. (4) Mid-bar chord change replans from the next step. (5) MIDI disconnect stops the fill and releases notes |
| Why | Owner: a one-cycle stop may feel delayed; no stuck or duplicate notes; no delayed response |
| Licence | Own |
| Expected benefit | **Target:** duplicate-note rate 0; stuck notes 0; note-in to first fill note < 10 ms on device (core decision < 1 ms); owner prefers the default stop behaviour on the Casio |
| Size / device | 0 MB |
| Benchmark / acceptance | Core tests + CT-X870IN checklist (R-5, full chords, melody above split, chord change mid-bar, cable unplug, paused/playing, tempo change, each stop mode); **complete only after the owner's Casio test** |
| Fallback | Current rules |

### C8 — Structure with confidence tiers

| Field | Content |
|---|---|
| Current | Foote boundaries (**measured** 4/4), grouping wrong (ABCBD), rule labels |
| Proposed | Bar/cycle-aligned features, key-invariant repeat grouping, vocal presence for section type, tiers: boundary, predicted type, guess. All-In-One as comparison (MIT weights by its author; NATTEN conversion **unknown**) |
| Why | Patterns are learned per repeated section |
| Licence | Own; All-In-One SAFE\* |
| Expected benefit | **Target:** exact grouping on the S1 structure set; no "Chorus" without vocal and repetition evidence |
| Size / device | 0 MB (1.4 MB/fold if All-In-One wins and converts) |
| Benchmark / acceptance | Boundary F, pairwise grouping F, label accuracy per tier on S1/S4/S6 |
| Fallback | Current analyzer + manual section editor |

### C9 — Instruments and tones (later programme)

| Field | Content |
|---|---|
| Current | Apple SoundAnalysis (**measured** 14/19 clean) + fingerprint matcher (**measured** lead 4/12, backing 2/12) |
| Proposed | Recognition (what plays) and matching (which TonePilot tone) kept separate. LAION-CLAP music (Apache-2.0, SAFE\*) is compared with a TonePilot model trained on real instrument audio (NSynth, Slakh2100, PDMX, owner recordings); library tones rendered at 3 registers × 2 velocities |
| Why | Measured weakness; scheduled after live fill |
| Licence | See checklist (SAFE\* items need data review) |
| Expected benefit | **Target:** Top-3 family-correct ≥ 10/12 leads, ≥ 9/12 backing (S1); better than baseline on real audio; owner blind preference ≥ 70% |
| Size / device | CLAP audio branch **unknown** (full model 776 MB fp32); own model ≤ 5 MB (**estimate**) |
| Benchmark / acceptance | Macro F1, Top-1/Top-3, listening |
| Fallback | Current matcher |

### C10 — Shared pipeline, inference interface and Android harness (Phase 1)

| Field | Content |
|---|---|
| Current | Import pipeline duplicated in `AppModel` (iOS) and `AppCore` (Android). No model inference on Android. No Android test source set |
| Proposed | **Phase 1:** `InferenceBackend` protocol in TonePilotCore (tensor in → tensor out, named model). iOS Core ML implementation. Android LiteRT implementation registered through the C bridge. A test backend that replays recorded outputs. Cross-platform fixtures (input audio + expected outputs) used by Linux core tests, iOS tests and an Android instrumented test on an emulator in CI. The import pipeline moves into the core. **Later phases:** each new stage lands on both platforms in the same phase |
| Why | Owner: Android parity from Phase 1, not Phase 7 |
| Licence | LiteRT Apache-2.0; ONNX Runtime MIT (if used) |
| Expected benefit | Identical analysis results on both platforms within a documented tolerance |
| Size / device | LiteRT runtime added to the APK (size **unknown**, Phase 1 measures) |
| Benchmark / acceptance | The fixture suite passes on Linux, iOS simulator and Android emulator; a sample model (Basic Pitch, 0.84 MB) runs through both back-ends with outputs matching within tolerance |
| Fallback | Keep the current per-platform orchestration while the shared pipeline stabilises |

## 4. Demucs and commercial builds

| Build | Separation | Condition |
|---|---|---|
| Personal (owner) | Current Demucs downloads | Allowed |
| Commercial / store | **None until cleared** | Written permission for `htdemucs`, or our own separator trained on cleared data (Slakh2100 CC BY 4.0, PDMX CC0, licensed multitracks), or analysis from the mix only |

Commercial builds must not download, bundle or call uncleared weights or use uncleared datasets. A build flag enforces this, and CI checks the licence manifest.

## 5. Protected functionality and regression

Melody Player (melody guide), ToneEngine, NoteRouter and MIDI, normal keyboard playing, Record, Song Studio and Tone Studio keep their current tests and the speed and crash stress test. Each phase adds a regression check, and no phase modifies them without a separate approval.
