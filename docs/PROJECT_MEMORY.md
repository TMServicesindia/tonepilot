# TonePilot — Project Memory

**Purpose:** durable memory of the whole working history with the owner, so any future session (or person) can continue without the chat. Read this first, then `CLAUDE.md` and the `docs/TONEPILOT_*.md` documents. Last updated: 1 November 2026.

---

## 1. Owner, setup and goals

- **Owner:** keyboard player in India (times are given in **IST**). Plays a **Casio CT-X870IN** (61 keys) over USB-MIDI into an **iPhone 15**; an Android app also exists.
- **Install:** unsigned `.ipa` from GitHub Releases, sideloaded with Sideloadly (never recommend free-signing/enterprise-certificate services).
- **What TonePilot is (owner's words, final):** a *song-aware accompaniment reconstruction system* — import a song, the app understands its accompaniment, extracts the actual pattern, and the player recreates it by playing simple chords (e.g. root–fifth) on the Casio. Instrument recognition and tone matching are secondary.
- **Owner's standing requirements:** every build smooth, fast, no crashes (see `CLAUDE.md`); report measured speed numbers with each build; give the download link when ready; the **full build (all tests) is mandatory** — the quick build (`ios-quick.yml`) and `[publish-anyway]` are one-off tools used only when the owner explicitly asks.
- **Constraints:** don't analyse ripped/pirated MP3s (e.g. MassTamilan files) or download from YouTube/piracy sites; use the owner's email only for identification; zero paid APIs; free and commercially usable models only; offline-first.

## 2. Repository and builds

- Repo `TMServicesindia/tonepilot` (public so the app can download models from GitHub Releases).
- iOS app (SwiftUI, `App/`), shared Swift package **TonePilotCore** (`Packages/TonePilotCore`), Android app (`android/`, Kotlin + C bridge), optional Python server (`server/`).
- Core tests: Docker `swift:6.0-noble` (`dockerd &` if down) → `swift test` (178 tests at v0.3.71).
- CI: `ios-build.yml` (core tests in release + speed budgets, MP3 check, instrument check, iPhone build, simulator speed & crash test, publishes `v0.3.N` release); `coreml-convert.yml` (Demucs Core ML + quality gate, publishes `models-v1`); `android-build.yml`; `ios-quick.yml` (one-off, no tests); `model-research.yml` (research-only licence scan; results on branch `research/model-scan`).
- Logs/artifacts from Actions are not downloadable from the cloud session (blob storage blocked); read **annotations** via the API instead. `huggingface.co`, `zenodo.org`, `magenta.tensorflow.org`, `essentia.upf.edu` are blocked in the session but reachable from CI.

## 3. History (chronological)

1. **Separation speed:** Demucs on-device; Core ML network (Neural Engine) with C++ fallback; random shift removed (deterministic); models downloaded in-app (`models-v1`: 4-part and 6-part); quality gate in CI.
2. **UI redesign**, then **speed & crash gate** for every build (CLAUDE.md rules).
3. **Song Arpeggio:** learned patterns per section; preview; then **live fill** (v3): fill starts after the player's R·5, speed from the song, 70% volume, softer and on top, full chord → silent, chord memory with reset, adjustable split point.
4. **Main tone vs Tone per section** as the user's choice; fixed icons; per-part volume sliders.
5. **Song parts:** Lead/Backing split of "other" (`LeadSplitter`), 6-part model, models downloaded in-app.
6. **Record tab:** records only app music + keyboard, starts on first key, exports MP3 (LAME).
7. **AI tones for mass songs (Hukum):** intensity, Apple sound classifier, power tones (Power Brass, Brass Stabs, Supersaw…), drive, chorus fallback, AI main tone. Owner said the Hukum main tone was "entirely ruined" and asked for ~"98% exact" tones.
8. **Phase B:** supersaw unison, filter envelope, velocity brightness, 26-tone Film Tone Library (90s→2026), era filters.
9. **Quick build** requested once ("for this time alone") → `quick-2`; full build `v0.3.67` (publish-anyway once).
10. Owner: "the entire app was messed; previous build better" → reverted advice to `v0.3.61`; found and fixed:
    - **Stuck notes** (mono held-key list kept stale keys after tone switches; only one of two stereo voices glided; chords on mono tones) → v0.3.70.
    - **Song Arpeggio melody bug** (melody notes above the split changed the chord) → v0.3.70.
    - **Live fill freeze** (deadlock: `LiveFill` held a non-recursive lock while the arpeggiator's callbacks took the same lock) → `LiveFill` moved to core with separate locks, tests prove old design hung → **v0.3.71**.
11. **ToneMatcher/PartMatcher** (analysis-by-synthesis tone matching) + 20 Indian film instruments (mandolin, sarangi, kuzhal, kombu, tanpura, duduk, …). Owner's real-song test: poor — sections all "Cinematic Low Strings" + "Tanpura-like Drone"; the "Guess 21%" badge is section-name confidence, not tone quality (confusing label).
12. Owner asked for an expert listener (musician + sound engineer + sound designer) and suggested tools (Songscription, Klangio, La Touche Musicale, Mirelo, ACE Studio; models RoFormer, Demucs, SOME, ROSVOT, VOCANO, Sheet Sage). Evaluated: commercial tools are reference only; SOME (MIT) candidate for vocals; Sheet Sage non-commercial; RoFormer weights unlicensed.
13. **Architecture & Models** Claude Doc: https://claude.ai/artifact/V7byAXXNTFPCC5Nrx8aDGf (note: it lists Demucs as "MIT" — true for code only).
14. **Phase 0 audit** (owner's assignment; no production code changed) → `docs/TONEPILOT_*.md`, revisions 1–3, owner reviews each time.

## 4. Audit findings (measured 1 Nov 2026, synthetic songs rendered from GeneralUser GS)

| Area | Result |
|---|---|
| Tone matching | lead 4/12 exact (7/12 family); backing 2/12 (5/12) |
| Beats | F 0.92 with drums, **0.52 without** |
| Tempo | 18/24 (6 half/double/×1.5) |
| Time signature | **10/24** |
| Chords | 70% of bars; minor keys 25–44%; 7ths/inversions 75% |
| Sections | boundaries 4/4; grouping wrong (ABCBD vs ABABC) |
| ArpeggioLearner | **100% degrees, step F 1.00 with true beats/chords** → inputs are the bottleneck |
| Apple classifier | 14/19 clean instruments (CI) |

Licensing: **Demucs weights not cleared for commercial use** (README: weight licence "not clear"; MUSDB18-HQ "other-nc"; 6-part "likely" NC) → personal builds only until cleared. Verified at source: Beat This! MIT (code+weights), Basic Pitch Apache-2.0 (LiteRT 0.84 MB), BTC chords MIT (12 MB), All-In-One weights MIT (author, 1.4 MB/fold), LAION-CLAP music Apache-2.0, NSynth/Slakh2100/GuitarSet CC BY 4.0. Rejected (non-commercial): madmom, Essentia, MERT, MuQ, FCPE, Sheet Sage, Open-Unmix umxl. Full detail: `docs/TONEPILOT_AI_MODEL_RESEARCH.md`, `docs/TONEPILOT_LICENSING_CHECKLIST.md`, scan in `docs/research/`.

## 5. Approved direction (revision 3) and conditions

Chain: **rhythm (beat evidence → separate cycle inference) → harmony (hypotheses; bass = evidence) → note events (DSP probe default; Basic Pitch per stem only if better) → conservative accompaniment type (default no fill; false arpeggios = 0) → pattern learning preserving actual order/timing/duration/register/variations (objective checks + owner listening) → live fill (no invented thirds; stop modes compared; tested on the owner's Casio)**. Instruments/tones later (CLAP music vs own model on NSynth/Slakh). Android parity in every phase. SAFE\* ≠ commercial clearance. Protected (unchanged): Melody Player, ToneEngine, NoteRouter, MIDI, normal playing, Record, Song Studio, Tone Studio.

**Owner approval (1 Nov 2026): Phase 1 only, foundation, with conditions:**
1. Capture current import/analysis outputs as regression fixtures **before** changing `AppModel`/`AppCore`.
2. `SongImportPipeline` = behaviour-preserving migration; no algorithm redesign.
3. Keep old orchestration as fallback until equivalence is shown.
4. Test Core ML, LiteRT and ReplayBackend independently (contract tests, loading, errors, numeric tolerance).
5. Basic Pitch = test model only; not shipped, not a production dependency.
6. Android emulator integration tests; physical Android USB-MIDI validation stays for Phase 5.
7. Indian acceptance dataset with source, licence, annotations, train/test split; 20 clips = minimum start, not proof. Infrastructure may proceed in parallel; Phase 2 rhythm acceptance waits for a representative set.
8. Separate licence records (code, weights, deps, data); SAFE\* never passes the commercial gate.
9. Don't modify ToneEngine, NoteRouter, MIDI, LiveArpeggiator, LiveFill, Recorder, Melody Player, Song Studio, Tone Studio.
10. No algorithm replacement, no new production models, no user-visible change in Phase 1.

**Deliver before Phase 2:** updated docs; every file changed; iOS + Android build results; before/after pipeline equivalence report; backend contract-test results; benchmark baseline report; dataset manifest + licensing checklist; known issues and risks. **If a gate fails: stop and report, don't weaken it. Wait for explicit approval before Phase 2.**

## 6. Phase 1 status (iPhone side delivered; Android parity pending; awaiting owner approval)

- Owner (1 Nov): **"The primary testing is right now on iPhone, so prioritise that."** iPhone items first; Android LiteRT/emulator after.
- Delivery report: **`docs/TONEPILOT_PHASE1_REPORT.md`** (files changed, equivalence, contracts, builds, baselines, risks).
- Done: fixtures (68d2e23) → `SongImportPipeline` + `ImportPipelineFlags.useSharedPipeline` fallback (iOS `TPLegacyImportPipeline` default) → equivalence exact (tol 0) vs legacy and pre-migration fixtures; Android bridge identical.
- **Determinism fix** (owner-approved): `mixStems` Dictionary order + max tie-breaks (ArpeggioLearner, AutoArranger, StructureAnalyzer). Benchmarks unchanged vs audit.
- `InferenceBackend` + `InferenceContract` (8 checks) in core; ReplayBackend; C-callback backend (`tp_set_inference_callback`, `tp_inference_contract`, `tp_pipeline_check`) for Android; `CoreMLBackend` in the app (unused by features). Basic Pitch fixtures from official `nmp.tflite` (`inference-fixtures.yml`, branch `ci/inference-fixtures`).
- iPhone build (`ios-build.yml`) now also runs: Core ML contract (blocking, CPU 1e-3) — **PASS, max diff ~1e-6, 35.5 ms CPU / 16.9 ms all**; licence gate (personal) PASS; Indian-set validator.
- `bench.yml` (manual + nightly 21:17 UTC): baselines, run twice, must be identical; results pushed to branch `ci/bench-results`. Baselines = audit numbers exactly.
- Licence manifest `docs/LICENSES/manifest.json` + `Native/tools/licences/check_manifest.py` (commercial fails on Demucs by design).
- Indian set: `docs/benchmark/indian-set/` + `Native/tools/dataset/validate_indian_set.py`; **0 clips** (needs owner recordings).
- Build run 41291859865 (a4ab124): all tests/gates passed (launch 3.29 s, peak 157 MB, stress 843 s) but **release publish failed: 403 "Resource not accessible by integration"**; rerun requested (attempt 2).
- Linux core: 195 tests, 0 failures, 8 skipped. Session note: job logs ARE readable via `gh api repos/.../actions/jobs/<id>/logs` once a job finishes.
- **Pending:** Android x86_64 core build, LiteRT Kotlin back-end, JNI hook, androidTest + emulator job. Then wait for explicit Phase 2 approval.


## 6b. Phase 2 (rhythm) — owner said "Continue with other phases also. One by one slowly" (1 Nov)

- Report: **`docs/TONEPILOT_PHASE2_REPORT.md`**. Nothing wired into the app (no user-visible change).
- Beat This! small0 (sha256 6074be2c…) → Core ML via `beat-this-convert.yml` (branch `ci/beat-this`): diff 1.9e-5 vs PyTorch. Swift front-end/post-processing (`Rhythm/BeatThis.swift`) identical to official (log-mel 6.4e-5; torchaudio here divides magnitudes by sqrt(n_fft)).
- `RhythmCycleInference` (`Rhythm/RhythmCycle.swift`): confident/ambiguous/unknown; accents = bass + chord change; longest cycle whose start beats every other position; double/half checks; model–accent disagreement blocks confidence.
- Rhythm benchmark (36 rendered songs incl. khanda 5, misra 7, adi 8; `bench.yml` macOS job → branch `ci/rhythm-results`): current metre 6/36 (83% wrong-confident); **cycle stage on current beats 31/36, 0% wrong-confident**; Beat This! + cycle 12/36, 3%; Beat This! beat F 0.80 vs current 0.82 (no drums 0.75 vs 0.82); 16–18 s per 4-min song on CI Mac.
- **Gate failed: Beat This! not adopted.** Cycle stage stays off until real Indian clips (0 so far).
- `CoreMLBackend` now lives in TonePilotCore (`#if canImport(CoreML)`).
- **Launch gate failing on CI today:** a4ab124 a2 4.55 s, b0eb8ae 4.93 s, control v0.3.71 9.28 s (passed 3.47 s this morning) → runner slowness. No release since v0.3.71. Owner to decide: re-run later, or change launch measurement (gate change = owner's call).


## 6c. Phase 3 (harmony) — owner: "Re-run the build later and start Phase 3" (1 Nov, ~17:00 IST)

- Full iPhone build re-run scheduled for 23:30 IST (scheduled task trig_01A9w7uttFtRtFQmBXdzQjVE; push latest main without [skip ci]).
- Report: **`docs/TONEPILOT_PHASE3_REPORT.md`**. `Harmony/HarmonyHypotheses.swift`: NNLS notes on a log-frequency spectrum, bass as evidence, triads with optional 7th, key bonus, weak melody top voice, drone rule (Sa–Pa steady, no third; tonic = root of fifth chain), long beats split at 0.6 s, ranked alternatives. 1.37 s per 4-min song.
- Step 3: 3 timbres per note in NNLS; melody-first strength (≥3 notes below melody); accompaniment-stem mode (20% leakage); held-out 3 (110 BPM, +3 st, untouched): current 46% / mix 81% / **stem 83%**, minor 100%, half-bar 100%, drone 100%, alts 94%. Weak: inversions (clavinet) 15/47, pedal (tremolo strings) 23/47. Reverted: bass-overtone discount (killed roots). 3.12 s/4-min. Not switched on.
- Owner suggested masstamilan.dev songs for learning → declined (piracy site; standing rule); offered owner recordings / CC BY-CC0 / permission.
- `HarmonyBenchmarks` (3 sets): current 73/59/66% beat accuracy vs **new 90/89/82%**; minor 50→84/85/70%; half-bar 23→100%; drone 0→100/90/31%; alternatives 82→98/98/92%. Held-out 2 (84 BPM) is the only untouched set: targets **not met** there. Not wired into the app.


## 6d. Phase 4 start and Tamil cinema dataset survey (1 Nov, ~18:30 IST)

- Phase 4 step 1: `Benchmarks/AccompanimentBenchmarks.swift` (9 section kinds, true inputs). Current learner: **false arpeggios 7/7** (both orders); real arpeggios learned well (step F 1.00, degrees 19/20). Classifier (default no fill) is next.
- Owner sent sources to "train": masstamilan (piracy, excluded); sajeevan16/tamil-songs-corpus (lyrics text only); code-mohanprakash/tamil (librosa features from masstamilan rips); HF Thanushs25/tamil-audio-emotion-classification (195 WAV of Tamil *speech*, no licence). None usable.
- Owner's dataset brief → `docs/benchmark/tamil-cinema/` (SOURCE_SURVEY.md, catalogue.json with 20 songs and train/dev/test by song identity, README). CI survey `dataset-survey.yml` → branch research/dataset-survey (205 HF datasets, 123 Zenodo records): **no lawful Tamil cinema audio anywhere**. Saraga Audiovisual (CC BY 4.0, classical) is a candidate for rhythm-cycle acceptance after licence text check. Route: owner Casio recordings (preferred), written permission, or purchased copies for private evaluation only.
- Incident: `git ls-tree -l` on a blob-less clone fetched ~108 MB (spectrogram PNGs) from AMAAI-Lab repo; stopped, names only read, deleted unopened.


## 6e. Instrument recognition project (owner: "Priority: Highest", 1 Nov ~19:00 IST)

- Deliverables 1–7 in **`docs/TONEPILOT_INSTRUMENT_RECOGNITION_PLAN.md`** (audit, candidate comparison, dataset/licensing plan, baseline report, fine-tuning feasibility, hybrid C proposal, size/cost). **No implementation until owner approval.**
- Audit facts: recognition = Apple SNClassifySoundRequest v1 on stems (iOS only; Android has none) → 13 families per section, no exact/unknown; tone matching = ToneMatcher (analysis-by-synthesis). The 4/12·7/12·2/12·5/12 numbers are *tone matching* on rendered GM songs; 14/19 is Apple family recognition on clean GM phrases. Nothing measured on real film music.
- Candidates: EfficientAT (MIT repo) best size/quality for hybrid; YAMNet (Apache code; weights licence to confirm); LAION-CLAP music (Apache, large); PANNs (CC BY 4.0 weights); MS-CLAP (comparison).
- Phase 4 paused after its benchmark baseline (false arpeggios 7/7).


## 6f. Indian film music accuracy-first strategy (owner, 1 Nov ~19:30 IST)

- Owner reframed: Indian film music (Tamil/Telugu/Hindi) is the primary domain for every feature; instrument Analyser + Maker first; larger licensed TRAIN set (20 songs = sealed TEST only); "accuracy improved" only on unseen real recordings; build TonePilot's own Indian-music intelligence layer.
- First deliverable (8 parts): **`docs/TONEPILOT_INDIAN_FILM_STRATEGY.md`**. Awaiting approval; no large training, no production change.
- Tooling committed (not wired): `Native/tools/instruments/taxonomy.json` v2 (families incl. Indian percussion; sources acoustic/electronic/imitation/unknown), `Benchmarks/InstrumentSetRender.swift` (FluidR3 GM MIT train bank vs GeneralUser test bank; solo + timed layered). FluidR3 licence verified MIT (Debian copyright).


## 6g. Zero-budget consolidated strategy (owner's final instruction, 1 Nov ~20:00 IST) — governing

- **`docs/TONEPILOT_ZERO_BUDGET_STRATEGY.md`** supersedes the Indian-film strategy where they differ. Zero budget (no paid APIs/datasets/GPUs/commissioned recordings); as many real songs as legitimately accessible; verified ground truth before any accuracy claim; status buckets in every report.
- **`docs/TODO.md`**: the master to-do list (owner asked for it). Keep it updated.
- Annotation schema `docs/benchmark/annotation.schema.json` + `Native/tools/dataset/annotations.py` (validator + coverage report).
- Outreach drafts (not sent): `docs/outreach/`.
- **No-fill-unless-sure** `Analysis/AccompanimentClassifier.swift` (not wired): evidence = activity, density, bar repeatability, chord-tone share, simultaneity; benchmark gated learner: false arpeggios 0/7 (dev, held-out 88 BPM, held-out-2 112 BPM), unwanted fills 0/4; arpeggios kept 1/2, 2/2, 1/2. maxSimultaneity 2.7 = midpoint of dev classes; otherwise initial thresholds.
- **Owner (~21:00 IST): iPhone/iOS main priority, Android second. The whole strategy and to-do list is for iOS first.**
- **Android parity:** x86_64 core build (matrix, non-blocking), JNI `pipelineCheck`, `android/app/src/androidTest/.../CoreParityTest.kt` reading shared fixtures, emulator job (reactivecircus, API 30) → **passes** (run 41314957089). APK still arm64-only (`-PtpAbis` selects ABIs).
- **First proxy instrument results** (run 41315008400, synthetic): A unusable (Apple 2% exact/94% unknown); C heads: EfficientAT 59% exact/75% family (best, layered window F1 0.37), PANNs 55/77, YAMNet 54/73, CLAP 28/41 (under-measured: 1 s windows). EfficientAT Core ML fp16 9.9 MB, 4.5 ms/window. Too many confident wrong answers → calibrate next. `docs/benchmark/INSTRUMENT_PROXY_RESULTS.md`.
- **Gates (1 Nov evening):** Gate 1 v2 (NSynth cross-domain DEV): EfficientAT+head ≤5% wrong family on TEST at 41% coverage (94% selective); fails on 1 s clips; poor on NSynth-test (GM-only training doesn't transfer) → v3 adds streamed NSynth-train + short DEV (run 41325343802). Gate 2 (macos-26): fp16 9.9 MB 99.5% family agreement, int8 97.2%, 6-bit rejected; Swift front-end 2.2e-5, Accelerate 0.12 s/4-min; TonePilot Lab (Lab/, separate app) built (run 41326170801). Mac runners: macos-15 arm64 capacity exhausted, macos-14 retiring → use macos-26 (Xcode 26) for research jobs.
- Instrument proxy benchmark pipeline: `.github/workflows/instrument-bench.yml` (render → variants → YAMNet/EfficientAT/PANNs/CLAP + Apple → evaluate A/C) → branch ci/instrument-bench. First run 41312723399.

## 6h. Gate 1 / Gate 2 decisions (owner, 2 Nov ~00:30 IST) — see strategy §6d

**Gate 1**
- Plain EfficientAT + head C stays the official candidate under the DEV rule; C-agree is not adopted (worse on NSynth).
- No more threshold-only variants. Next lever: licensed real recordings (Indian instruments, acoustic vs imitation pairs).
- The 5% wrong-family target is not met on every condition, and the dashboard says so.

**Launch gate**
- Median of five launches, limit 4 s.
- Every timing is recorded with mean and p90, plus the old avg-of-3 view; runner info and history go to `ci/launch-history`.
- Control comparison: `launch-control.yml` (v0.3.71 vs main, same runner class).
- The peak-memory gate never matched Xcode's metric name ("Memory Peak Physical (tonepilot), kB"), so the 1.5 GB check never ran. Fixed.

**Gate 2**
- Core ML conversion, numerics and Mac timings are measured.
- Every iPhone number is pending (TonePilot Lab rebuilt: run 41340171940, with simulator/physical labels, peak footprint and 3 repeats).

**Shadow mode** (developer-only, off by default)
- Enabled only by files in `Documents/Developer`; the production recognizer stays authoritative.
- Writes only `Documents/Developer/shadow/*.json`.
- Code: `App/Sources/Services/DeveloperShadowMode.swift` + core `Instruments/ShadowInstruments.swift`.

**Not approved:** replacing production recognition, enabling it for users, and Android implementation.
**No publishing** until the gate passes and the 403 publishing permission is fixed.

## 6i. Competitor research, Phase A (owner, 2 Nov ~01:00 IST)

Research only; no app code changed for it.
- Three documents in `docs/research/`: competitor research, gap analysis, roadmap proposal.
- Evidence came from web search; direct fetches of the vendor sites were blocked by the session network. No app was tested hands-on.

Recommendations awaiting the owner:
- Position TonePilot as **song → arrangement → keyboard performance**.
- Accompaniment approach **E (hybrid)**: keep the separated backing and generate only the left-hand song pattern.
- First milestone **M1, "Play this song on my Casio"**.
- Don't build: a separator, a DAW/note editor, sheet music, text-to-music, or generic grooves.

**Wait for explicit approval before implementing any of it.**

## 6j. Launch investigation (2 Nov ~01:30 IST) — every timing kept

Five launches per build; medians; same runner image throughout (macos15 20261028.0489.1, M1 virtual, Xcode 16.4, iPhone 16 iOS 18.5).

| Run | Build A median (values) | Build B median (values) |
|---|---|---|
| 41340066348 | v0.3.71 **2.19 s** (2.74, 2.28, 1.83, 2.19, 1.89) | main **3.50 s** (3.81, 3.50, 3.14, 3.50, 3.66) |
| 41342418353 | v0.3.71 **2.12 s** (2.39, 2.02, 2.49, 2.12, 1.94) | main **3.51 s** (5.35, 3.39, 2.93, 3.79, 3.51) |
| 41342424229 | (control failed: short SHA) | main **3.74 s** (4.30, 3.74, 3.42, 4.01, 3.67) |
| 41342430415 | (control failed: short SHA) | main **2.67 s** (4.69, 2.57, 2.77, 2.67, 2.61) |
| 41343134530 | 007f6b2 **3.52 s** (5.00, 3.48, 3.14, 3.52, 4.10) | main **2.44 s** (2.40, 2.44, 2.51, 2.61, 2.01) |
| 41343140345 | 9f9ad63 **3.36 s** (3.73, 3.32, 3.36, 3.75, 3.02) | main **2.65 s** (2.56, 2.65, 2.86, 1.75, **19.17**) |

Reading:
- Medians fall into two clusters, about 2.1–2.7 s and about 3.4–3.7 s, whatever the code.
- Main was measured in both clusters, and both older commits were measured slow.
- This fits two kinds of host machine behind the same runner label, not a code regression. One 19.17 s single launch shows why the gate uses the median.
- It doesn't rule out a small regression. The next step is a same-machine A/B: both builds in one job, launches interleaved.

**Same-machine A/B (run 41386232452, 2 Nov):** one M1 virtual machine (macos15 20261028.0489.1, Xcode 16.4), builds launched alternately A, B, A, B, A, B, 5 launches each per round, every timing kept.

| Build | n | Median | Mean | p90 | Round medians |
|---|---|---|---|---|---|
| A: v0.3.71 (91a92c5) | 15 | 2.15 s | 2.27 s | 2.40 s | 2.31, 2.15, 2.05 |
| B: main (56d78ee) | 15 | 1.99 s | 2.45 s | 2.68 s | 2.63, 1.87, 2.08 |

- Outliers kept: B 7.34 s (round 1); A 4.42 s (the first, cold launch).
- **Conclusion: no launch regression.** B − A median = −0.16 s; B was slower in 2 of 3 rounds by small margins.
- The earlier 1.3 s gap was machine bimodality, not the code.
- Main (including developer shadow mode) built for testing on the simulator. This is a compile check, not a full build gate.

## 6k. Focus reset: Instrument Analyser accuracy first (owner, 2 Nov)

- The owner brought the focus back to the Instrument Analyser for Tamil/Telugu/Hindi film music. CI and release work are only supporting checks.
- Two separate systems: **Instrument Analyser** (what plays, and when) and **Tone Maker** (which sound recreates it).
- Research and audit delivered: dataset research, model comparison, accuracy roadmap, taxonomy v3 proposal, licensing checklist rows.

Key findings:
- **Sanidha** is the only verified permissive (CC BY 4.0) real Indian multitrack source.
- **Saraga 1.5** is non-commercial.
- Our "PANNs" was CNN14; **CNN10** (equal size to EfficientAT) has never been tested.
- No gate is measurable on real Indian audio yet.

Stop: no production change, no major training, no release before approval.

## 6l. Sound palette addendum + E2 (owner, 2 Nov)

- The owner widened the target to the full **2000–2026 film sound palette**: guitars and effects, synth families, processed vocals, sound design.
- The analyser output becomes six independent dimensions: identity, source type, character, likely processing, role, timing. It never names a plugin or synth model.
- Report: `docs/TONEPILOT_SOUND_PALETTE_RESEARCH.md`.
- **E2 (owner: "go ahead"):** PANNs CNN10 encoder in `embed.py`; workflow `instrument-e2.yml` reuses bench run 41328362434's clips and outputs, so the comparison uses an identical protocol. Results go to branch `ci/instrument-e2`.

## 6m. Sound-palette coverage and data plan (2 Nov)

- **Owner reaffirmed:** the 31-composer palettes are coverage guidance only, never labels, priors or ground truth. A claim is promoted only with a linked source.
- No winner is reported before E2 completes.
- Report: `docs/benchmark/SOUND_PALETTE_COVERAGE_AND_DATA_PLAN.md`. Inventory: `docs/benchmark/sound_palette_inventory.json` (165 terms).
- The coverage gap is real Indian recordings; there is an owner recording programme with priorities and a specification.

## 6n. E2 result + a correction (2 Nov)

**E2 (run 41386940981):** PANNs CNN10 does not replace EfficientAT + head C.
- DEV coverage 60% vs 73%; NSynth coverage 24% vs 50%; layered F1 0.28 vs 0.35; 4.5× slower.
- C stays official. All synthetic/NSynth.

**Correction:** the v4 claim "the source head never says imitation (28/28)" was wrong; it was read from a log line cut at 250 characters.
- The true v4 figure is 31 imitation / 28 acoustic / 1 electronic of 60 imitation clips.
- Fixed in INSTRUMENT_PROXY_RESULTS, MODEL_COMPARISON and TODO.

## 6o. Tone recreation direction (owner, 2 Nov)

- The owner separated **instrument identity** (what is playing) from **perceptual tone match** (which tone sounds closest).
- Identity must never restrict the tone search. The goal is to recreate the sound on the CT-X870IN.
- The two-stage screening matcher is not shipped (no sealed-TEST gain, 2× slower); it is on branch `research/tone-shortlist`.
- Proposal (research only): `docs/research/TONEPILOT_TONE_RECREATION_PROPOSAL.md`. No build until the T1–T5 experiments are approved and measured.

## 6p. Tone references built automatically, no manual recording (owner, 2 Nov)

- Plan: `docs/benchmark/OPEN_SOURCE_TONE_REFERENCE_EXPANSION_PLAN.md`.
- Verified licences:
  - FluidR3 MIT; MuseScore General MIT;
  - NSynth, TinySOL, Slakh CC BY 4.0;
  - Meta Open Sound, VSCO 2 CE, VCSL CC0;
  - Iowa MIS evaluation-only;
  - Casio/Yamaha factory samples rejected.
- Design: references serve two roles: playable candidates, and learning a cross-source similarity. More references alone don't fix the hand fingerprint (measured).
- Smallest next experiment: E-4 (frozen embedding cosine vs the fingerprint on cross-bank DEV).

## 6q. Nearest-sound tone search: built into the app (2 Nov; owner: "complete all phases, give me the best build")

**Phases completed, each gated by measurement:**
1. **E-4:** frozen embeddings beat the fingerprint cross-bank (DEV).
2. **E-5:** + harmonic isolation of the part from its notes (DEV best). LDA rejected.
3. **Device parity:** a numpy copy of the Swift front-end (2.2e-5) with a power-domain mask; the Swift mask matches Python to 8.5e-6.
4. **Sealed TEST (MuseScore General, run once):** right family, lead 1→6/12, backing 1→9/12; shipping fingerprint 1/12 and 1/12.

**In the app:**
- `PerceptualToneService` loads the bundled EfficientAT Core ML fp16 (`App/Resources/ML`, compiled on first use) and the precomputed tone tables (`tone_table_harmonic/plain.json`, from CI).
- The separated parts are re-decoded at 32 kHz.
- Lead parts are masked with the extracted notes; backing is plain.
- The fingerprint fits EQ/reverb to the chosen tone.
- **Per-section lead sounds** (`Song.sectionLeadMatches`: pallavi, charanam, interludes) feed the right hand, and therefore the main tone.
- Fallback: if the model or tables can't load, the app uses the previous fingerprint matcher.

**Gates added:**
- core tests + speed budget (0.28 s per 24 s part without Core ML);
- full-build "Nearest-sound search contract" (bundled model + Swift front-end vs PyTorch embedding, cosine > 0.99; tables valid);
- licence manifest entry (SAFE\*: MIT code/weights, AudioSet data).

**First full build (run 41415425679) failed the new contract, before publishing:**
- Gate 2's Core ML export was traced on 100-frame windows. The Swift front-end, the tone tables and the sealed TEST all use 101 frames (1 + n/hop).
- Fix: re-exported with input [1,1,128,101], same settings as Gate 2 (`tone-model.yml`, run 41416938342, branch `ci/tone-model`).
- Measured on Mac CI: embedding cosine 0.99999 vs PyTorch fp32 on 36 windows; same nearest tone 36/36 with compute units "all".
- With CPU only, 35/36 against the harmonic table. The one change was an unmasked sawtooth scored against the harmonic table, a pairing the app never uses.
- Fp16 is 9.86 MB; 7.5 ms per window on the Mac.
- The app now also turns the search off (fingerprint fallback) if the model's input shape isn't [1,1,128,101].

**Not validated yet:** real film songs; physical iPhone timing (G2.4).

## 6r. Tone fit T3 + first passing full build with the nearest-sound search (2 Nov, owner: "start the tone fine-tuning while the build waits")

**Tone fit T3:**
- `ToneFitter` built and unit-tested.
- Pre-registered DEV gate (independent judges CNN10 + MFCC against the part alone): **FAIL** in runs 41434478851 and 41438106229.
- It helps performed leads; it doesn't help as-is parts.
- Kept off after runs 1–2.
- Owner then: "Go ahead with the tone fit fixes". Fixes:
  - leakage-robust measurement;
  - note-by-note consistency;
  - melody parts only.
- Run 41497516817 **PASSED**: 10/17 better, 0 worse. Switched on (`PartMatcher.fitsPlaying = true`).
- This was the third attempt on the same DEV banks; still to confirm on a new sealed bank and by the owner's listening test.
- Details: `benchmark/INSTRUMENT_PROXY_RESULTS.md`.

**Full builds:**
- The tone editor froze in the stress test on iOS 17. Cause: a half-height sheet with its rows below the fold. Fix: the editor opens full height, and the test waits for the editor itself.
- Full build 41434482796 (macos-14, iOS 17.4) **passed every gate**:
  - launch median 1.52 s;
  - peak memory ~140 MB;
  - tone fitting budget 0.58 s.
- macos-15 runners were unavailable five times on 2 Nov. Manual full builds of `main` (runner input) now publish too, with the same gate.

## 7. Open owner decisions

- Draft permission emails to the Demucs author/Meta (commercial weights) and the GeneralUser GS author (training use) — offered, awaiting yes.
- Owner recordings for the Indian acceptance set (Casio performances; Tamil/Telugu/Hindi film-style accompaniments; Indian rhythmic cycles).
- Agree benchmark gates (`docs/TONEPILOT_BENCHMARK_PLAN.md` §6).
- **Launch gate on shared CI simulators** (re-run 1 Nov 23:32 IST, run 41334484025):
  - Launch averaged 4.34 s against the 4 s limit (three runs: 4.23 / 5.29 / 3.50 s, 17% spread). Every other check passed.
  - The launch path is unchanged since v0.3.71, which launched in 3.47 s. The control build v0.3.71 took 9.28 s on an earlier slow runner, so this is runner noise.
  - Options offered: (a) re-run again; (b) median of 5 launches (same 4 s limit); (c) one-off `[publish-anyway]`.
  - **Owner chose (b), 2 Nov, with safeguards (§6h). Implemented.**
  - The publish 403 (Settings → Actions → Workflow permissions → Read and write) is still unresolved; publishing has not been reached since.

## 8. Release history (latest first)

(1 Nov 23:32 IST re-run: launch 4.34 s > 4 s, not published) · (v0.3.72 attempted: Phase 1 iPhone foundation; publish 403) · v0.3.71 (live fill deadlock fix; all gates passed; launch 3.47 s) · v0.3.70 (stuck notes, arpeggio melody bug, ToneMatcher, 20 instruments; launch 3.86 s) · v0.3.67 (publish-anyway; Film Tone Library) · quick-2 · v0.3.61 (Record; owner's preferred older build) · earlier v0.3.x.
