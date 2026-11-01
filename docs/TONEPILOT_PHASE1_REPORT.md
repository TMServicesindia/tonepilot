# TonePilot — Phase 1 Delivery Report

**Date:** 1 November 2026 (IST) · **Scope:** Phase 1 (foundation) only, as approved with conditions.
**Priority change from the owner:** "The primary testing is right now on iPhone, so prioritise that."
The iPhone side of Phase 1 is delivered first. The Android LiteRT back-end and emulator tests are
**not done yet**; see §8. **Phase 2 has not started and will not start without explicit approval.**

## 1. Summary against the 10 conditions

| # | Condition | Status |
|---|---|---|
| 1 | Fixtures captured before changing AppModel/AppCore | **Done**: commit 68d2e23, before any orchestration change (007f6b2) |
| 2 | Behaviour-preserving `SongImportPipeline` | **Done**: equivalent at tolerance 0 (§3) |
| 3 | Old orchestration kept as fallback | **Done**: `ImportPipelineFlags.useSharedPipeline` (iOS: `TPLegacyImportPipeline` default turns it off); legacy code paths kept intact |
| 4 | Core ML, LiteRT, Replay tested independently | Replay **passes**; C-callback (the LiteRT path's ABI) **passes** on Linux; Core ML: **PASS** in the iPhone build (CPU and all compute units); **LiteRT Kotlin back-end itself: not yet built (Android deferred)** |
| 5 | Basic Pitch is a test model only | **Done**: used in CI only; nothing in the app references or downloads it |
| 6 | Android emulator tests; USB-MIDI stays Phase 5 | **Not done yet** (deferred for iPhone priority). Physical Android USB-MIDI validation is a Phase 5 item |
| 7 | Indian acceptance dataset | **Infrastructure done** (manifest, schema, validator, CI check). **0 clips**; needs owner recordings |
| 8 | Separate licence records; SAFE\* never passes commercial | **Done**: `docs/LICENSES/manifest.json` + gate; commercial gate fails today on Demucs weights, by design |
| 9 | Protected components untouched | **Done**: no changes to ToneEngine, NoteRouter, MIDI, LiveArpeggiator, LiveFill, Recorder, Melody Player, Song Studio, Tone Studio |
| 10 | No algorithm replacement / new models / visible change | **Done**, with one approved exception: the determinism fix (§4) |

## 2. Every file changed (since 15282f4, the approved docs)

**Core (TonePilotCore)**
- `Sources/TonePilotCore/Pipeline/SongImportPipeline.swift` (new): shared import pipeline + flag.
- `Sources/TonePilotCore/Inference/InferenceBackend.swift` (new): `InferenceBackend` protocol, `Tensor`, `ModelDescriptor`, `InferenceError`, `InferenceRegistry`, `ReplayBackend`.
- `Sources/TonePilotCore/Inference/InferenceContract.swift` (new): the contract every back-end must pass.
- `Sources/TonePilotCore/Analysis/SongAnalyzer.swift`, `ArpeggioLearner.swift`, `StructureAnalyzer.swift`, `Arrangement/AutoArranger.swift`: determinism fix only (fixed iteration order and tie-breaks; §4).

**Bridge (Android C interface)**
- `Sources/TonePilotBridge/AppCore.swift`: `analyze` uses the shared pipeline (legacy kept behind the flag).
- `Sources/TonePilotBridge/CAPI.swift`: `tp_set_inference_callback`, `tp_inference_contract`, `tp_pipeline_check`.
- `Sources/TonePilotBridge/CallbackInferenceBackend.swift` (new): back-end over a C callback (what the Android LiteRT back-end will plug into).
- `Sources/TonePilotBridge/FixtureCheck.swift` (new): normalisation and fixture check shared with Android.

**iOS app**
- `App/Sources/Services/AppModel.swift`: both import call sites use the shared pipeline (legacy behind the flag).
- `App/Sources/Audio/CoreMLBackend.swift` (new): Core ML back-end (not used by any feature yet).

**Tests and fixtures**
- `Tests/.../PipelineFixtureTests.swift`, `PipelineEquivalenceTests.swift`, `InferenceBackendTests.swift`, `CrossPlatformFixtureTests.swift` (new).
- `Tests/.../Benchmarks/AnalysisBaselineBenchmarks.swift`, `ToneMatchingBenchmarks.swift` (new; run only with `TP_SF2`).
- `Tests/.../Fixtures/pipeline/{mix-only,listened,stems-ios}.json` (recorded outputs).
- `Tests/.../Fixtures/inference/basic_pitch/*` (test-model input/outputs from the official `nmp.tflite`, ONNX cross-check).

**CI and tools**
- `.github/workflows/ios-build.yml`: Core ML contract step (blocking), licence gate and Indian-set check.
- `.github/workflows/bench.yml` (new): benchmark baselines, run twice, reproducibility check.
- `.github/workflows/inference-fixtures.yml` (new): generates the Basic Pitch fixtures.
- `Native/tools/inference/make_basic_pitch_fixture.py`, `Native/tools/inference_check/main.swift`, `Native/tools/licences/check_manifest.py`, `Native/tools/dataset/validate_indian_set.py` (new).

**Docs**
- `docs/PROJECT_MEMORY.md` (new), `CLAUDE.md` (points to it), `docs/LICENSES/manifest.json`, `docs/benchmark/indian-set/{README.md,manifest.json,clip.example.json}`, this report.

## 3. Before/after pipeline equivalence

Method: three deterministic songs (mix only; listened; iOS with stems + server melody + instrument
recogniser + tone matching + stem infos). Output songs are normalised (UUIDs mapped in fixed order,
dates removed) and compared field by field.

| Check | Tolerance | Result |
|---|---|---|
| Shared pipeline vs previous flow (same process), 3 cases | 0 (exact) | **Identical** |
| Shared pipeline vs fixtures recorded before migration, 3 cases | 1e-3 relative | **Identical** |
| Android bridge (`listenBegin/Append/Finish`) flag on vs off | 0 | **Identical** |
| Same input in 3 fresh processes | 0 | **Identical** (after §4 fix) |

## 4. Determinism finding (fixed with owner approval)

While recording fixtures, one learned arpeggio degree in the stems case changed between runs.
Causes: `mixStems` summed stems in Dictionary order (random per process in Swift), and several
"pick the max" decisions had no tie-break. Fixed by fixed iteration order (`StemInfo.Kind.allCases`)
and deterministic tie-breaks in ArpeggioLearner, AutoArranger and StructureAnalyzer. This changes
no algorithm; it removes run-to-run randomness. Results on borderline songs may differ from an
earlier run's result (which was itself random).

## 5. Back-end contract results

Contract checks: load of a missing file fails · run before load fails · load · wrong shape rejected ·
missing input rejected · output shapes · numeric tolerance · unload. The contract was shown to catch
a +0.01 error and a wrong shape.

| Back-end | Where | Tolerance | Result |
|---|---|---|---|
| ReplayBackend | Linux + macOS tests | 0 | **PASS** (proves the harness only, not real compatibility) |
| C-callback back-end (Android ABI) via `tp_*` C functions | Linux tests | 1e-3 | **PASS** |
| Core ML, CPU only (gate) | iPhone build (macOS) | 1e-3 | **PASS**: max \|diff\| note 5.7e-7, onset 6.3e-7, contour 9.5e-7; run 35.5 ms; all 8 checks ok |
| Core ML, all compute units (report) | iPhone build (macOS) | 5e-2 | **PASS**: same diffs; run 16.9 ms; all 8 checks ok |
| LiteRT on Android | — | 1e-3 | **Not run yet** (Android deferred) |

Reference outputs: official `nmp.tflite` (LiteRT); ONNX cross-check max |diff| 5.4e-7.

## 6. Builds

| Build | Result |
|---|---|
| Core tests, Linux (Docker swift:6.0-noble, release) | **195 tests, 0 failures, 8 skipped** (benchmarks without SoundFont, live server) |
| iPhone full build (`ios-build.yml`), attempt 1 (a4ab124) | All tests and gates **passed** (launch 3.29 s, peak 157 MB, stress 843 s); **publish failed**: GitHub 403 "Resource not accessible by integration" |
| Same build, attempt 2 | **FAILED speed gate: launch 4.55 s** (4.94 / 4.55 / 4.16; budget 4 s); everything else passed |
| Full build b0eb8ae (Phase 1 + Phase 2 code, not wired into the app) | **FAILED speed gate: launch 4.93 s** (6.24 / 4.57 / 3.97); Core ML contract, tests and stress test (820 s) passed |
| Control: v0.3.71 code (before Phase 1) on the same runners | Run [41299499585](https://github.com/TMServicesindia/tonepilot/actions/runs/41299499585): **launch 9.28 s** (13.09 / 12.00 / 2.74), failed the same gate. This is the code that launched in 3.47 s this morning, so today's simulator runners are slow. **Phase 1 did not slow the app** (its only start-up change is one settings read). Gate not weakened; the owner decides (§8) |
| Android build (`android-build.yml`) | Run [41291859834](https://github.com/TMServicesindia/tonepilot/actions/runs/41291859834): **success** |

Speed budgets (Linux release): engine 4.3% of real time; supersaw 5.5%; pattern learning 4.98 s per
242 s; analysis 4.21 s per 128 s; lead split 8.3 s per 240 s; tone matching 4.77 s.
iPhone build: launch **3.29 s** (budget 4 s); peak memory **157 MB** (budget 1.5 GB); stress test through every tab and Song Studio page passed, no crash or freeze. macOS speed budgets: engine 2.9%, supersaw 5.1%, pattern learning 2.16 s per 242 s, analysis 1.91 s per 128 s, lead split 4.0 s per 240 s, tone matching 2.31 s.

## 7. Benchmark baseline

Run [41293106922](https://github.com/TMServicesindia/tonepilot/actions/runs/41293106922) (`bench.yml`, Linux release, songs rendered from GeneralUser GS). **Reproducible**: two runs gave identical output (53 result lines). Full results on branch `ci/bench-results`.

| Area | Baseline |
|---|---|
| Tempo | 18/24 exact; 6 octave/metrical errors |
| Beats | F 0.72 overall; **0.52 without drums**, 0.92 with drums |
| Time signature | **10/24** |
| Chords | 70% exact (root + major/minor); 78% right root |
| Sections | boundary F 1.00; grouping ABCBD (truth A/B/A/B/C) |
| Arpeggio learner (true beats/chords) | step F 1.00; degrees 100%; grid right 2/5 |
| Tone matching | lead 4/12 exact (7/12 family); backing 2/12 (5/12) |

These match the Phase 0 audit numbers exactly, so the determinism fix (§4) changed no measured result.
Nightly runs (21:17 UTC = 02:47 IST) keep checking reproducibility.

## 8. Known issues and risks

1. **Android parity not delivered yet:** LiteRT Kotlin back-end, JNI hook, x86_64 core build and the
   emulator instrumented tests are still to do. Plan: x86_64 Swift core → LiteRT Gradle dependency →
   `LiteRtBackend.kt` behind `tp_set_inference_callback` → androidTest assets from the repo fixtures →
   emulator CI job. Physical Android USB-MIDI validation remains a **Phase 5** item.
2. **Indian set has 0 clips.** Phase 2 rhythm acceptance cannot start until a representative set exists.
3. **All baselines are synthetic** (GeneralUser GS renders); they say nothing about real film audio.
4. **Demucs weights are Personal only:** a commercial build fails the licence gate today.
5. Core ML GPU/Neural Engine numbers may use float16; only the CPU path is gated.
6. **Launch gate failing on CI runners today** (4.55 s, 4.93 s; the pre-Phase-1 control 9.28 s). No new release has been published since v0.3.71. Options for the owner: re-run the full build later; or change how launch is measured (e.g. median of 5, ignoring the first cold launch). That second option changes a gate, so it is the owner's decision.
7. **Release publish 403** on run 41291859865 (see §6). If the rerun fails the same way, the likely cause is the repository's Actions setting "Workflow permissions" (Settings → Actions → General); only the owner can check it.
8. The legacy pipeline flag must be removed in a later phase once the owner is satisfied.
9. The licence gate enforces recorded statuses; it is not legal advice.

## 9. Owner actions requested

- Approve (or not) Phase 2 — **nothing in Phase 2 starts before that**.
- Decide whether Android parity (§8.1) must finish before Phase 2 approval.
- Record the first Indian clips (see `docs/benchmark/indian-set/README.md`).
- Permission emails (Demucs, GeneralUser GS training use): drafts on request.
