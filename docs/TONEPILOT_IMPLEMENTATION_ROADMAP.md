# TonePilot — Implementation Roadmap

**Date:** 1 November 2026 · **Status:** awaiting the owner's approval. Phase 0 (this audit) is complete; nothing below has started.

**Order of work:** benchmark first, then rhythm (the measured bottleneck for Song Arpeggio), then accompaniment transcription and pattern learning, then instruments and tones. Each phase ships only through the full build and its own acceptance gate, and each can be rolled back on its own.

Effort is in engineering days of focused work (**estimates**). Model sizes are from official READMEs where stated, otherwise "to measure".

| Phase | Scope | Main files | New model / download | Effort | Acceptance (must hold) | Rollback |
|---|---|---|---|---|---|---|
| **0 Audit** | Repository audit, licences, baselines | `docs/` only | — | Done | Owner approval | — |
| **1 Licence verification** | Read the unreachable model cards (Hugging Face, Zenodo) in CI or with the network allowed; email GeneralUser GS author re training; record a licence manifest; decision on Demucs for commercial builds | `docs/`, `Native/LICENSES/` (new) | — | 1–2 | Every candidate classed SAFE / RESTRICTED / UNVERIFIED with a source | n/a |
| **2 Benchmark harness** | Turn the audit harness into `Packages/TonePilotCore/Tests/Benchmarks` (opt-in, env-gated); add S1 at 200 songs, `mir_eval` metrics in CI, JSON results artifact; start S3/S4 annotation | Tests, `.github/workflows/bench.yml` (new) | GeneralUser GS (already used) | 4–6 | Baseline reproduced in CI; numbers in `TONEPILOT_BENCHMARK_PLAN.md` §1 regenerated automatically | Remove workflow; no app impact |
| **3 Rhythm** (moved ahead of tones: it gates arpeggio accuracy) | Beat This! small → Core ML (+ ONNX for Android); fusion with `TempoAnalyzer`; meter from downbeats; one shared grid for structure, chords and arpeggio | `Analysis/TempoAnalyzer`, new `Analysis/BeatModel`, `SongAnalyzer`, `SectionInsights`, conversion workflow, `ModelStore` manifest | Beat This! small ~8.1 MB (MIT) | 6–9 | No-drum beat F ≥ 0.85; meter ≥ 20/24; added time ≤ 10 s per 4-min song on device (target); all existing gates | Feature flag falls back to `TempoAnalyzer` |
| **4 Harmony and structure (DSP)** | Bass-aware, key-aware chords; key-invariant repeat grouping; vocal-aware section types; confidence tiers; relabel the "Guess" badge | `HarmonyAnalyzer`, `StructureAnalyzer`, `SongAnalyzer`, Song Studio section card | none | 5–8 | Chords ≥ 85% (minor ≥ 75%); grouping exact on S1 structure set; no confident "Chorus" without vocal + repetition evidence | Keep old analyzers behind a flag for one release |
| **5 Accompaniment transcription + pattern learning** | Basic Pitch on piano/guitar/backing stems; `ArpeggioLearner` learns from note events (degree, octave, duration, accent, variations); phrase vs pattern classification; A/B validation preview | new `Analysis/NoteTranscriber`, `ArpeggioLearner`, `SongArpeggio`, `SongArpeggioView` | Basic Pitch (Apache-2.0; size to measure) | 8–12 | Degree accuracy ≥ 90% with **estimated** beats/chords on S1; owner approves patterns on 10 real sections | Fall back to the current onset/probe learner |
| **6 Live Song Arpeggio** | Third rule (no invented thirds below confidence); stop after a silent cycle; per-section validated patterns only; tempo scale during paused practice (exists) | `LiveArpeggiator`, `LiveFill`, `AppModel+Arpeggio` | none | 3–4 | Duplicate-note rate 0; latency < 1 ms per note in core; zero stuck notes in stress + device test; owner sign-off on the Casio | Revert rule flags |
| **7 Instruments and tones** | Train the TonePilot Timbre model on cleared data; library embeddings at build time (3 registers × 2 velocities); retrieval + existing EQ/reverb fit; arranger policy fix (vocal sections vs hooks); CLAP as benchmark comparison only | new `Arrangement/TimbreModel`, `PartMatcher`, `AutoArranger`, training scripts under `Native/timbre/` | Own model ≤ 5 MB (target) | 10–15 | Top-3 family-correct ≥ 10/12 leads and ≥ 9/12 backing on S1; better than baseline on S4; owner blind preference ≥ 70% vs current | Flag back to `ToneMatcher` ranking |
| **8 Melody and separation** | Compare `MelodyExtractor` vs Basic Pitch on vocals (S3/S4); adopt only on a measured gain; separation alternatives only with SAFE weights and downstream gains | `MelodyExtractor`, `StemSeparator` | none new by default | 3–5 | Note F gain on real vocals; bends preserved; no separation change without SAFE weights | Keep current |
| **9 Regression and release** | Full build, device tests on the Casio, Android parity check for shared-core features | all | — | 2–3 | All gates green; owner acceptance | Previous release stays published |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Beat This! or the Timbre model doesn't convert to Core ML cleanly | Medium | Phase slips | Convert in CI with numeric checks against PyTorch (as done for Demucs); ONNX fallback |
| Basic Pitch weak on dense real stems | Medium | Pattern accuracy below gate | Run on the stem with the clearest accompaniment; keep current learner as fallback and cross-check |
| Training-data licences don't clear (GeneralUser, Slakh, NSynth) | Medium | Phase 7 limited to own synth renders | Ask authors early (Phase 1); record own instrument samples |
| Demucs weights unsuitable for commercial release | High (per its README) | Commercial builds lack separation | Personal builds unaffected; seek permission or train own separator later |
| Added analysis time on device | Medium | Slower imports | Windowed inference, small variants first, CI budget |
| Android lags (no Core ML) | High today | Feature gap | ONNX/TFLite export as an acceptance item for each model; pipeline moved into the core |

## Dependencies between phases

Phase 2 before everything (no change without a baseline). Phase 3 before 5 and 6 (patterns need bars). Phase 4 before 5 (patterns need chords). Phase 7 is independent of 3–6 and can run in parallel once Phase 1 clears training data.
