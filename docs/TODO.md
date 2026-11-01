# TonePilot — To-Do List

**Updated:** 1 November 2026, ~20:40 IST (owner's additions A–G and priority order included). Source: `TONEPILOT_ZERO_BUDGET_STRATEGY.md` (governing) and the phase reports.

Status tags:
- ✅ Completed
- 🔨 Implemented, not tested
- 🧪 Tested on synthetic data
- 🎻 Tested on licensed real recordings
- 🇮🇳 Tested on real Tamil/Telugu/Hindi
- ⏳ Pending (mine)
- 📝 Awaiting ground truth
- 👤 Awaiting owner

Rules that apply to every item:
- zero budget;
- no audio from piracy sites;
- nothing switched on in the app without owner approval;
- synthetic results are never reported as film-music accuracy.

---

## Execution priority (owner, 1 Nov)

1. **Dataset and ground-truth foundations** (sections 2, 2A, 2B)
2. **Instrument Analyser** (section 3)
3. **Instrument Maker** (section 4)
4. Song intelligence: rhythm, chords and bass, sections, melody, separation (section 5)
5. Accompaniment and Live Song Arpeggio (section 6)
6. Android parity and release readiness (sections 7, 8)

**In parallel, always:** critical bug fixes, stability, security, regression (section 1).
**Next milestone:** a reliable instrument benchmark on actual instruments in Tamil, Telugu and Hindi music.

## 0. Owner actions (blocking)

| # | Item | Status |
|---|---|---|
| 0.1 | Repo Settings → Actions → General → Workflow permissions = "Read and write" (release publish got 403) | 👤 |
| 0.2 | Review and approve/edit the drafts in `docs/outreach/` (musician letter, Demucs email, GeneralUser GS email). Nothing is sent without approval | 👤 |
| 0.3 | Legal check: private evaluation of lawfully held film songs; pre-1965 recordings | 👤 |
| 0.4 | Supply or record real songs for the sealed TEST (start with the 20 catalogue songs). **Depends on 0.3 (legal clearance)**: owning a recording does not automatically allow every kind of processing or evaluation | 👤 (after 0.3) |
| 0.5 | Identify "Muvvala Navvakala" (film/composer) and "The Rose theme" | 👤 |
| 0.6 | Verify a prioritised set of pre-annotated sections (not every song; see 2B) | 👤 📝 |
| 0.7 | Listening A/B for Instrument Maker and accompaniment (later) | 👤 |
| 0.8 | Casio CT-X870IN live tests (Song Arpeggio, live fill) | 👤 |
| 0.9 | Optional, not blocking: free Freesound API key | 👤 |

## 1. Builds and regression

| # | Item | Status |
|---|---|---|
| 1.1 | Full iPhone build re-run, scheduled 23:30 IST (regression check only, not accuracy evidence) | ⏳ |
| 1.2 | Launch-gate failures (4.55 s, 4.93 s; control v0.3.71 at 9.28 s → slow runners). Decide re-run vs measurement change | 👤 |
| 1.3 | Publish a release once the gate passes (needs 0.1) | ⏳ |
| 1.4 | Keep all core tests green (215 now), speed budgets, nightly reproducible benchmarks | ✅ ongoing |

## 2. Documentation and data foundations

| # | Item | Status |
|---|---|---|
| 2.1 | Zero-budget strategy, dataset architecture, catalogue plan, annotation workflow, licence register, report structure, phased plan | ✅ |
| 2.2 | Annotation schema + validator + coverage report (`docs/benchmark/annotation.schema.json`, `Native/tools/dataset/annotations.py`) | ✅ (tested on an example) |
| 2.3 | Move the 20-song catalogue to per-language JSONL; add Tamil metadata from the CC0 source | ⏳ |
| 2.4 | Find CC0/CC BY metadata sources for Telugu and Hindi film songs | ⏳ |
| 2.5 | Private on-device evaluation tool (dev builds only; audio stays local; only hashes, annotations and scores saved) | ⏳ (after 0.3) |
| 2.6 | Licensed instrument audio collection: Freesound / Wikimedia Commons per-file licence check; Saraga Audiovisual licence confirmation; NSynth/Slakh subsets; manifest with SHA-256 | ⏳ |
| 2.7 | Confirm the YAMNet weights licence | ⏳ |

## 2A. Real-world film-song catalogue (large-scale, growing)

| # | Item | Status |
|---|---|---|
| A.1 | Continuously expanding catalogue of **legally accessible** Tamil, Telugu and Hindi film songs. No 20/60 limit; no invented target | ⏳ |
| A.2 | **Keep audio and metadata separate**: metadata catalogue (can scale to thousands; CC0 sources) vs audio holdings (only lawfully held, private, never committed) | ⏳ |
| A.3 | Track tiers separately per language: collected · imported · analysed · annotated · verified · evaluated · excluded (reason) | ✅ format (coverage report); ⏳ data |
| A.4 | Coverage balance: decades, composers, styles, section types, arrangement density. Report imbalance | ⏳ |
| A.5 | **Legal dependency:** audio-based evaluation of film songs only after 0.3. Purchase ≠ automatic evaluation/training rights | 👤 |

## 2B. Ground-truth annotation workflow (formal dataset task)

| # | Item | Status |
|---|---|---|
| B.1 | Schema: multiple simultaneous instruments, instrument vs family level, timestamps, acoustic/electronic/imitation/unknown, audibility, overlaps, confidence, evidence, verification status | ✅ (`annotation.schema.json`, validator) |
| B.2 | **AI pre-annotation:** analyser predictions written as `unverified` suggestions, never counted as ground truth | ⏳ |
| B.3 | Correction and verification: owner correction, second-listen or independent verification → `verified` | ⏳ tool, 👤 time |
| B.4 | **Prioritise verification:** pick representative sections (instrument coverage, density, language balance) rather than annotating every song. A small verified set beats a huge unverified one | ⏳ |
| B.5 | Annotation helper (local): spectrogram + stems + suggested labels; save JSON per song | ⏳ |

## 3. Instrument Analyser (highest priority)

| # | Item | Status |
|---|---|---|
| 3.1 | Audit of current recognition (Apple, iOS only, 13 families) vs tone matching | ✅ |
| 3.2 | Taxonomy v2 (+ acoustic / electronic / imitation / unknown) | ✅ |
| 3.3 | Proxy clip generator (FluidR3 train bank vs GeneralUser test bank, timed layered tracks, variants) | ✅ tested locally |
| 3.4 | Proxy benchmark A (Apple, YAMNet, EfficientAT, PANNs, CLAP) and C (embeddings + head): run 41315008400 | 🔨 running in CI |
| 3.5 | Add NSynth real-sample set (families, acoustic/electronic/synthetic) to the benchmark | ⏳ |
| 3.6 | Add licensed real recordings (GuitarSet, Saraga, CC clips) | ⏳ (needs 2.6) |
| 3.7 | Fine-tuning experiment (B), only if C leaves a measured gap; resumable on free Colab/Kaggle | ⏳ (approval for large training: 👤) |
| 3.8 | Five-stage analyser prototype (content → family → instrument → time aggregation → tone mapping), Core ML + LiteRT, shadow mode | ⏳ (approval: 👤) |
| 3.9 | Real-song evaluation per language with verified annotations | 📝 |
| 3.10 | **Indian instrument coverage tracker** (dataset clips and recognition accuracy, real vs synthetic) for bansuri, nadaswaram, shehnai, veena, sitar, santoor, tabla, mridangam, dholak, ghatam, kanjira, thavil. Today: real licensed clips = **0 for all**; synthetic imitations exist only for bansuri, nadaswaram, shehnai (GM), veena, sitar (GM), santoor | ⏳ |
| 3.11 | **Real-world accuracy dashboard** per language (Tamil / Telugu / Hindi): songs collected, annotated, evaluated; exact accuracy; family accuracy; multi-label P/R/F1; unknown detection and calibration; coverage by family and arrangement complexity | ⏳ (structure ✅ in strategy §6) |

## 4. Instrument Maker (equal priority)

| # | Item | Status |
|---|---|---|
| 4.1 | Keep recognition separate from tone matching (violin → "Strings" family → closest Casio tone, all three kept) | ✅ design |
| 4.2 | Similarity benchmark: spectral, envelope, attack/decay, velocity response, playable range vs isolated originals | ⏳ |
| 4.6 | **Chain test:** original section → isolated instrument → TonePilot tone → comparison, **inside the full arrangement** | ⏳ |
| 4.7 | Layered-tone tests (e.g. strings + choir pad) | ⏳ |
| 4.8 | **CT-X870IN listening validation** (played through the Casio) | 👤 |
| 4.3 | Indian tones from licensed samples or synthesis (bansuri, nadaswaram, veena, santoor, …) to replace or improve the "-like" GM variants | ⏳ |
| 4.4 | Layer editing, EQ/reverb shaping driven by recognition | ⏳ |
| 4.5 | Listening A/B protocol and runs | ⏳ + 👤 |

## 5. Song analysis (built, off until real validation)

| # | Item | Status |
|---|---|---|
| 5.1 | Beat This! evaluated, not adopted (no improvement) | 🧪 ✅ |
| 5.2 | Rhythm-cycle inference: 31/36, 0% wrong-confident | 🧪 |
| 5.3 | Harmony hypotheses: 83% on the untouched held-out set with stems; weak on inversions/pedal | 🧪 |
| 5.4 | Sections: fix repeat grouping; instrument changes per section | ⏳ |
| 5.5 | Melody / phrase analysis benchmark | ⏳ |
| 5.6 | Validate 5.2–5.5 on real songs | 📝 |
| 5.7 | Separation on Indian orchestral/electronic mixes (SDR on licensed multitracks) | ⏳ |

## 6. Accompaniment Maker and Live Song Arpeggio

| # | Item | Status |
|---|---|---|
| 6.1 | Accompaniment benchmark: current learner gives **7/7 false arpeggios** | 🧪 ✅ |
| 6.2 | **No-fill-unless-sure classifier** (`AccompanimentClassifier`, NOT wired into the app): false arpeggios **7/7 → 0/7** and unwanted fills **4/4 → 0/4** on dev and both held-out sets; real arpeggios kept 1/2, 2/2, 1/2 (triplet on guitar sometimes blocked: safe side) | 🧪 (synthetic); real-section validation 📝 + listening 👤; activation 👤 |
| 6.3 | Pattern fidelity with estimated (not true) beats and chords | ⏳ |
| 6.4 | Owner listening on 10 real sections | 👤 |
| 6.5 | Live Song Arpeggio: no-third-when-unsure, stop modes, Casio test | ⏳ + 👤 |

## 6F. Free-compute management (zero budget)

| # | Item | Status |
|---|---|---|
| F.1 | Checkpoint and resume for every long job (embeddings cached per model version; training checkpoints) | ⏳ (benchmark caches outputs per model ✅) |
| F.2 | Training time estimates before any run; experiment registry so the same experiment never runs twice | ⏳ |
| F.3 | Free GPU quota tracking (Colab/Kaggle) with CPU fallback (GitHub Actions) | ⏳ |
| F.4 | Model size, memory, inference speed and battery benchmarks (CI + iPhone/Android) | ⏳ (CPU speed and parameters ✅ in benchmark) |
| F.5 | No paid compute or recurring services | ✅ rule |

## 7. Android parity (project requirement)

| # | Item | Status |
|---|---|---|
| 7.1a | x86_64 core build + JNI `pipelineCheck` + instrumented `CoreParityTest` (shared mix-only fixture) + emulator CI job | ✅ **passes** on the API 30 x86_64 emulator (run 41314957089: 1 test, 0 failures); APK unchanged |
| 7.1b | LiteRT Kotlin back-end behind `tp_set_inference_callback`; Basic Pitch contract on the emulator | ⏳ |
| 7.2 | Android instrument recognition (none today) via the same LiteRT model | ⏳ (after 3.8) |
| 7.3 | Android separation and Song Arpeggio | ⏳ |

## 8. Licensing before any commercial release

| # | Item | Status |
|---|---|---|
| 8.1 | Demucs weights permission (email drafted) | 👤 |
| 8.2 | GeneralUser GS training permission (email drafted) | 👤 |
| 8.3 | Attribution file in the app (CC BY, MIT, Apache, LGPL notices) | ⏳ |
| 8.4 | Commercial licence gate passing | ⏳ (blocked by 8.1) |
