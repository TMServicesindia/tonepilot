# TonePilot — Implementation Roadmap (revision 2)

**Date:** 1 November 2026 · **Status:** awaiting the owner's approval. Revision 2 follows the owner's order: licensing and benchmark → rhythm → chords → accompaniment extraction → live validation on the Casio → instruments and tones → Android parity and release. **Android parity is an acceptance item in every phase**, not only the last.

Effort in focused engineering days (**estimates**). Change IDs (C1–C10) refer to `TONEPILOT_RECOMMENDED_ARCHITECTURE.md`.

| Phase | Scope | Changes | Main files | New downloads | Effort | Acceptance (all must hold) | Fallback |
|---|---|---|---|---|---|---|---|
| **1 Licensing + benchmark foundation** | Licence manifest for every dependency (done for candidates via `docs/research/model_scan.md`); Demucs permission request; GeneralUser GS training permission; inspect Carnatic CC BY datasets' provenance; benchmark harness in the repo (opt-in, env-gated) with `mir_eval` metrics; reproduce baselines; start the real-audio set (GuitarSet, Slakh, owner recordings, CC0/CC BY tracks) with annotations | — | `Packages/TonePilotCore/Tests/Benchmarks/`, `.github/workflows/bench.yml`, `docs/research/`, `Native/LICENSES/` | Benchmark data in CI only (never in the app) | 6–9 | Baselines regenerated in CI; ≥ 20 annotated real clips; licence manifest complete | — |
| **2 Rhythm** | Beat This! small conversion (Core ML + LiteRT/ONNX) with numeric checks vs PyTorch; fusion with TempoAnalyzer; `RhythmCycle` (beats per cycle, subdivision, accents, confidence); All-In-One as comparison | C1, C2, (C8 comparison) | new `Analysis/BeatModel`, `Analysis/RhythmCycle`, `TempoAnalyzer`, `SongAnalyzer`, `InferenceBackend` (new), conversion workflow, `ModelStore` | Beat This! small ~8.1 MB | 8–11 | No-drum beat F ≥ 0.85 (S1) and better than TempoAnalyzer on real audio; cycle length ≥ 85%; "unclear" on rubato; ≤ 10 s added per 4-min song on iPhone 15; **same results on Android** within tolerance | Flag → TempoAnalyzer |
| **3 Chords and harmony** | Bass-aware, key-aware, beat-level chord HMM; sevenths/inversions/slash; drone/modal state; BTC comparison | C3 | `HarmonyAnalyzer`, `SongAnalyzer`, chord display | none (BTC 12.2 MB only if it wins) | 6–8 | ≥ 85% beat-level accuracy, minor keys ≥ 75% on S1; half-bar changes found; better than current on real audio; Android parity | Current analyzer |
| **4 Accompaniment extraction** | Note events per stem (probe vs Basic Pitch vs both); accompaniment-type classifier; pattern learning from notes with variations; A/B validation UI; structure grouping (C8) because patterns are learned per repeated section | C4, C5, C6, C8 | new `Analysis/NoteEvents`, `Analysis/AccompanimentType`, `ArpeggioLearner`, `SongArpeggio`, `StructureAnalyzer`, `SongArpeggioView` | Basic Pitch 0.84 MB (only for stems where it wins) | 12–16 | Degree accuracy ≥ 90% with **estimated** beats and chords (S1); note F per stem reported, method chosen per stem; type accuracy ≥ 85%; zero arpeggios in hook/solo/none sections; owner approves 10 real sections; Android parity of the analysis | Current learner |
| **5 Live Song Arpeggio on the Casio** | Third rule, stop after a silent cycle, validated patterns only, mid-bar chord changes, disconnect handling; live fill wired into Android `AppCore` | C7, C10 (live part) | `LiveArpeggiator`, `LiveFill`, `AppModel+Arpeggio`, `AppCore` | none | 4–6 | Device checklist on the CT-X870IN: R-5, full chords, melody above split, chord change mid-bar, cable unplug, paused + tempo change; duplicate notes 0; stuck notes 0; < 1 ms per note; owner sign-off; works on an Android phone with USB-MIDI | Current rules |
| **6 Instruments and tones** | Recognition vs matching as separate outputs; CLAP music vs TonePilot Timbre model (trained on NSynth + Slakh + PDMX + own recordings); library embeddings at 3 registers × 2 velocities; arranger policy (vocal sections vs hooks) | C9 | new `Arrangement/TimbreModel`, `PartMatcher`, `AutoArranger`, `Native/timbre/` | Winner only (own ≤ 5 MB target; CLAP audio branch size to measure) | 12–18 | Top-3 family-correct ≥ 10/12 leads, ≥ 9/12 backing (S1); better than baseline on real audio; owner blind preference ≥ 70%; Android back-end works | Current matcher |
| **7 Android parity, regression, release** | Shared `SongImportPipeline` in the core; full regression on both platforms; device performance (time, memory, battery); release notes with licence attributions (CC BY datasets, Apache/MIT notices) | C10 | `AppModel`, `AppCore`, core pipeline | — | 4–6 | All gates green on iOS and Android; attribution file complete; owner acceptance | Previous release stays published |

## Dependencies

Phase 1 before everything. Phase 2 before 3 and 4 (chords and patterns sit on the beat/cycle grid). Phase 3 before 4. Phase 5 after 4. Phase 6 is independent of 2–5 and may start research once Phase 1 clears data, but takes engineering priority only after Phase 5.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Beat This! or BTC doesn't convert cleanly to Core ML / LiteRT | Medium | Phase delay | CI conversion with numeric checks (as for Demucs); ONNX Runtime fallback on both platforms |
| Rhythm models trained on Western datasets underperform on Indian film rhythms | Medium | Weak cycles | `RhythmCycle` keeps "unclear" honest; owner-annotated Indian clips in the benchmark; fusion with onset analysis |
| Basic Pitch weak on dense stems | High for orchestral/strings | Pattern errors | Per-stem method choice; probe fallback; accompaniment-type gate |
| Demucs permission not granted | Medium–high | No separation in commercial builds | Personal builds unaffected; own-separator option (C) |
| Carnatic CC BY sets turn out to be generated audio | Unknown | Less Indian evaluation data | Rely on owner recordings and CC0/CC BY film-style tracks |
| Android runtime size or speed | Medium | Larger APK | Small models only; LiteRT first |
