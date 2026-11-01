# TonePilot — Implementation Roadmap (revision 3)

**Date:** 1 November 2026 · **Status:** awaiting the owner's explicit approval; **no production code is modified until then.**

Revision 3 changes:
- The shared inference interface, the Android test harness and the cross-platform fixtures move into **Phase 1**.
- Every later phase delivers its feature on iOS and Android together.
- The real Indian acceptance set is mandatory from Phase 1.
- Phase 7 becomes regression and release only.

Effort is focused engineering days (**estimates**). Change IDs (C1–C10) refer to `TONEPILOT_RECOMMENDED_ARCHITECTURE.md`. Acceptance thresholds are **targets** (`TONEPILOT_BENCHMARK_PLAN.md` §6).

| Phase | Scope | Changes | New downloads | Effort (est.) | Acceptance (all must hold) | Fallback |
|---|---|---|---|---|---|---|
| **1 Foundation** | Licence records (checklist complete for every candidate); permission requests (Demucs author/Meta, GeneralUser GS author); benchmark harness in the repo with `mir_eval` metrics; baselines reproduced in CI; **real Indian acceptance set started** (owner recordings + licensed recordings, annotated); **`InferenceBackend` (Core ML + LiteRT + replay test backend)**, **Android instrumented test harness on an emulator**, **cross-platform fixtures**; shared import pipeline in TonePilotCore | C10 | Basic Pitch 0.84 MB as the **test model** for both back-ends (CI only, not shipped) | 12–16 | Checklist complete; baselines regenerated in CI; ≥ 20 annotated real Indian clips; fixture suite green on Linux, iOS simulator, Android emulator; test model outputs equal within tolerance on both back-ends; protected-feature regression green | Keep per-platform orchestration |
| **2 Rhythm** | Beat This! small conversion (Core ML + LiteRT) with numeric checks vs PyTorch; beat fusion; **separate `RhythmCycle` inference** with confident/ambiguous/unknown | C1, C2 (C8 comparison: All-In-One) | Beat This! small ~8.1 MB | 8–11 | Beat/cycle targets met on S1 **and** improvement on S6 (real Indian); wrong confident cycle labels ≤ 5%; ≤ 10 s added per 4-min song (iPhone 15), Android measured; both platforms equal within tolerance | TempoAnalyzer |
| **3 Harmony** | Hypothesis-based chords: bass as evidence, bass-free chroma, key context, temporal smoothing, alternatives, drone/modal and no-chord states, any-beat changes; BTC comparison | C3 | none (BTC 12.2 MB only if it wins on real audio) | 6–9 | Chord targets on S1; improvement on S4/S6; drone passages never forced to a triad; both platforms | Current analyzer |
| **4 Accompaniment extraction** | DSP probe always; Basic Pitch per stem type only where better; conservative accompaniment-type classifier; pattern learning that preserves order, timing, duration, register, variations; validation with objective note checks **and** owner listening; structure grouping | C4, C5, C6, C8 | Basic Pitch only for winning stem types | 12–16 | False-arpeggio rate **0** in hook/solo/sparse/sustained sections; pattern targets with estimated inputs; owner approves 10 real sections; both platforms | Current learner; no fill when uncertain |
| **5 Live Song Arpeggio** | Third rule; stop modes benchmarked (immediate, one cycle, configurable); validated patterns only; mid-bar changes; disconnect handling; live fill on Android | C7 | none | 4–6 | **Owner's CT-X870IN test passed**; duplicate notes 0; stuck notes 0; latency target met; protected features unchanged; Android with USB-MIDI | Current rules |
| **6 Instruments and tones** | Recognition vs matching; CLAP music vs TonePilot model on real-instrument data; library embeddings | C9 | Winner only | 12–18 | Matching targets; better than baseline on real audio; listening ≥ 70%; data licence records complete; both platforms | Current matcher |
| **7 Regression and release** | Full regression on both platforms; device performance (time, memory, battery); attribution file; commercial-build licence gate | — | — | 3–5 | All gates green; licence gate passes for the build type; owner acceptance | Previous release stays published |

## Phase 1 — files that would change

**New files**

| Path | Purpose |
|---|---|
| `Packages/TonePilotCore/Sources/TonePilotCore/Inference/InferenceBackend.swift` | Protocol: named model, tensors in/out, errors; registry used by analysis stages |
| `Packages/TonePilotCore/Sources/TonePilotCore/Inference/Tensor.swift` | Minimal float tensor (shape + contiguous storage) shared by both back-ends |
| `Packages/TonePilotCore/Sources/TonePilotCore/Inference/ReplayBackend.swift` | Test back-end that returns recorded outputs (fixtures) |
| `Packages/TonePilotCore/Sources/TonePilotCore/Pipeline/SongImportPipeline.swift` | Shared import → analyse → arrange flow (moved from `AppModel`/`AppCore`) |
| `Packages/TonePilotCore/Tests/TonePilotCoreTests/InferenceBackendTests.swift` | Contract tests for back-ends and the registry |
| `Packages/TonePilotCore/Tests/TonePilotCoreTests/Fixtures/` | Cross-platform fixtures (short licensed audio, expected outputs, tolerances) |
| `Packages/TonePilotCore/Tests/Benchmarks/` (opt-in target, env-gated) | Benchmark harness from the audit + `mir_eval`-compatible outputs |
| `App/Sources/Audio/CoreMLBackend.swift` | iOS implementation of `InferenceBackend` |
| `android/app/src/main/java/com/tonepilot/app/inference/LiteRtBackend.kt` | Android implementation (LiteRT Interpreter) |
| `android/app/src/androidTest/java/com/tonepilot/app/FixtureTests.kt` | Android instrumented tests running the shared fixtures through JNI |
| `.github/workflows/bench.yml` | Benchmarks + baselines (manual and nightly; not a release gate yet) |
| `Native/tools/convert/` | Model conversion scripts with numeric checks (Core ML + LiteRT) |
| `docs/LICENSES/manifest.json` + `docs/TONEPILOT_LICENSING_CHECKLIST.md` (exists) | Machine-readable licence records; CI check for commercial builds |
| `docs/benchmark/indian-set/MANIFEST.md` | Per-clip source, licence, annotator, split (audio stored outside the app and outside public git if needed) |

**Modified files**

| Path | Change |
|---|---|
| `Packages/TonePilotCore/Sources/TonePilotBridge/CAPI.swift` | C entry points to register the Android inference callback and run the shared pipeline |
| `Packages/TonePilotCore/Sources/TonePilotBridge/AppCore.swift` | Use `SongImportPipeline` instead of its own orchestration |
| `App/Sources/Services/AppModel.swift` | Use `SongImportPipeline`; register `CoreMLBackend` |
| `android/app/src/main/cpp/tonepilot_jni.c` | Bridge the inference callback (JNI ↔ C) |
| `android/app/build.gradle.kts` | LiteRT dependency; `androidTest` source set; test runner |
| `.github/workflows/android-build.yml` | Emulator job running the instrumented fixture tests |
| `.github/workflows/ios-build.yml` | Run fixture tests; licence-manifest check step |
| `Packages/TonePilotCore/Package.swift` | Fixture resources; opt-in benchmark target |

**Not touched in Phase 1:** ToneEngine, NoteRouter, MIDI input, LiveArpeggiator, LiveFill, Recorder, Melody Player, Song Studio and Tone Studio screens, model download of Demucs, any analysis algorithm's behaviour (the pipeline move must produce identical outputs, verified by fixtures).

## Dependencies

Phase 1 before everything. 2 before 3 and 4 (grid). 3 before 4 (chord degrees). 5 after 4. 6 may start research after Phase 1 clears data, but has lower engineering priority than 2–5.

## Risks

| Risk | Likelihood (est.) | Impact | Mitigation |
|---|---|---|---|
| Pipeline move changes behaviour | Medium | Regressions | Fixtures must match current outputs exactly before any algorithm work |
| Android emulator CI is slow or flaky | Medium | Slower feedback | Small fixtures; nightly full run, per-PR subset |
| Beat This!/BTC conversion issues | Medium | Delay | Numeric checks in CI; ONNX Runtime fallback on both platforms |
| Western-trained rhythm models on Indian cycles | Medium | Weak cycles | C2 is separate and can say "unknown"; S6 is mandatory |
| Basic Pitch weak on dense stems | High for strings/orchestra | Pattern errors | Per-stem choice; DSP probe wins by default |
| Indian acceptance set too small | Medium | Weak evidence | Owner recordings start in Phase 1; grow per phase |
| Demucs permission refused | Medium–high | No separation in commercial builds | Personal builds unaffected; own separator option |
