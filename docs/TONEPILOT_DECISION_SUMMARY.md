# TonePilot — Decision Summary (revision 3)

**Date:** 1 November 2026 · **Status:** final refinement for the owner's approval. **No production code has been modified; implementation starts only after explicit approval.**

**What TonePilot is becoming:** a song-aware accompaniment reconstruction system. It listens to a song, understands its accompaniment, extracts the actual pattern, and lets the player recreate it by playing simple chords on the Casio CT-X870IN. Most effort goes to the Song Arpeggio chain: rhythm → harmony → note events → accompaniment type → pattern → live fill. Instruments and tones come later and stay separate.

Documents:
- `TONEPILOT_ARCHITECTURE_AUDIT.md`: what exists, measured baselines.
- `TONEPILOT_AI_MODEL_RESEARCH.md`: candidates and licences.
- `TONEPILOT_RECOMMENDED_ARCHITECTURE.md`: revision 3, change register C1–C10.
- `TONEPILOT_IMPLEMENTATION_ROADMAP.md`: revision 3, including the Phase 1 file list.
- `TONEPILOT_BENCHMARK_PLAN.md`: revision 3, acceptance criteria in §6.
- `TONEPILOT_LICENSING_CHECKLIST.md`: new; per-dependency records.

## Measured vs target vs unknown

| Fact | Kind | Value |
|---|---|---|
| Arpeggio learner with true beats/chords | **Measured** (synthetic) | 100% degrees, step F 1.00 |
| Beat F without / with drums | **Measured** (synthetic) | 0.52 / 0.92 |
| Time signature | **Measured** (synthetic) | 10/24 |
| Chords (bar level) | **Measured** (synthetic) | 70%; minor keys 25–44% |
| Tone matching lead / backing (exact) | **Measured** (synthetic) | 4/12 / 2/12 |
| Any result on real Tamil/Telugu/Hindi film audio | **Unknown** | Phase 1 builds the set; every stage must pass on it |
| No-drum beat F ≥ 0.85; cycle ≥ 85%; chords ≥ 85% (minor ≥ 75%); false arpeggios 0; pattern degrees ≥ 90% with estimated inputs | **Targets** | For approval |
| Beat This! / BTC / Basic Pitch speed on iPhone and Android | **Unknown** | Phases 1–4 measure |
| Sizes: Beat This! small ~8.1 MB, BTC 12.2 MB, Basic Pitch LiteRT 0.84 MB | **Source** (READMEs / Hugging Face) | — |
| Effort per phase | **Estimates** | See roadmap |

## Revision 3 changes (owner's review)

1. **Android from Phase 1:** `InferenceBackend` (Core ML + LiteRT + replay test backend), Android instrumented test harness on an emulator, cross-platform fixtures, shared import pipeline. Every later phase lands on both platforms.
2. **Rhythm:** Beat This! gives beat/downbeat **evidence** only; a separate cycle-inference stage decides, with confident/ambiguous/unknown states, and never forces a Western label.
3. **Harmony:** bass is root **evidence**; bass + chroma + key + time context + optional BTC give ranked hypotheses; drone/modal passages are never forced to a triad; changes allowed on any beat.
4. **Transcription:** Basic Pitch is an optional experiment per stem type; the existing DSP probe wins unless Basic Pitch measures better.
5. **Accompaniment type:** a conservative classifier where the default is no fill; **false-arpeggio rate = 0** is the primary gate, reported separately from accuracy.
6. **Pattern validation:** objective checks (order, timing, duration, register, degrees, variations) **and** owner listening, both required.
7. **Live fill:** immediate, one-cycle and configurable stop behaviours benchmarked; zero stuck or duplicate notes; latency gate; complete only after your CT-X870IN test.
8. **Real Indian audio:** owner recordings and licensed Indian-style recordings are **mandatory** acceptance data.
9. **Licensing:** SAFE\* is not commercial clearance. Separate records for code, weights, dependencies and data; a commercial-build gate in CI; no uncleared Demucs weights or datasets in commercial builds.
10. **Protected functionality:** Melody Player, ToneEngine, NoteRouter, normal playing, Record, Song Studio and Tone Studio stay unchanged and regression-tested.

## Approval conditions (as set by the owner, built into the plan)

1. Phase 1 delivers licence records, reproducible benchmarks and the shared iOS/Android inference interface.
2. Every model must improve on the current implementation on independent real audio before adoption.
3. Indian rhythmic cycles, minor keys, drones, half-bar chord changes and dense accompaniment are explicitly tested.
4. Song Arpeggio preserves actual note order, timing, duration, register and variations.
5. Live fill is tested on the owner's CT-X870IN before it counts as complete.
6. No feature compromises Melody Player, Tone Studio, recording or normal keyboard playing.
7. Commercial builds use no uncleared Demucs weights or datasets.

## Phase 1 at a glance

| Item | Detail |
|---|---|
| Scope | Licence records and permission requests; benchmark harness and baselines in CI; real Indian acceptance set started (≥ 20 annotated clips); `InferenceBackend` with Core ML, LiteRT and replay back-ends; Android instrumented fixture tests; shared import pipeline (outputs unchanged) |
| New downloads | Basic Pitch LiteRT/Core ML as the back-end **test model** (CI only, not shipped) |
| Files | Listed in the roadmap ("Phase 1 — files that would change") |
| Not touched | ToneEngine, NoteRouter, MIDI, LiveArpeggiator, LiveFill, Recorder, Melody Player, Song Studio and Tone Studio screens, Demucs download, any analysis algorithm's behaviour |
| Effort | 12–16 days (estimate) |
| Owner input needed | Approval; permission emails (drafts on request); first owner recordings for the Indian set |
