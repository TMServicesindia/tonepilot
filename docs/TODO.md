# TonePilot — To-Do List

> **Platform rule (owner): this whole strategy and to-do list is for the iPhone/iOS app first.** Every model, tone, benchmark and feature is built, measured and validated on iPhone (Core ML, on-device) before Android. Android parity follows as the second priority.

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

**Platform priority (owner, 1 Nov ~21:00 IST): iPhone/iOS first; Android second.** Every feature lands and is validated on iPhone first; Android parity follows.
**In parallel, always:** critical bug fixes, stability, security, regression (section 1).
**Next milestone:** a reliable instrument benchmark on actual instruments in Tamil, Telugu and Hindi music.

## IA. Instrument Analyser accuracy-first plan (owner, 2 Nov) — **TOP PRIORITY; research done, awaiting approval**

Docs:
- [`TONEPILOT_INSTRUMENT_DATASET_RESEARCH.md`](TONEPILOT_INSTRUMENT_DATASET_RESEARCH.md)
- [`TONEPILOT_INSTRUMENT_MODEL_COMPARISON.md`](TONEPILOT_INSTRUMENT_MODEL_COMPARISON.md)
- [`TONEPILOT_INSTRUMENT_ACCURACY_ROADMAP.md`](TONEPILOT_INSTRUMENT_ACCURACY_ROADMAP.md)
- [`benchmark/TAXONOMY_V3_PROPOSAL.md`](benchmark/TAXONOMY_V3_PROPOSAL.md)

Chord/Arpeggio and Tone Maker enhancements are paused until the analyser gates are agreed.

| # | Item | Status |
|---|---|---|
| IA.1 | **Sanidha** (CC BY 4.0, Carnatic multitrack: violin, mridangam, ghatam, tanpura, voice; minimal bleed): the access request needs a GT guest VPN account, so draft the email | 👤 approve the draft (not sent) |
| IA.2 | Saraga Audiovisual: verify the file-level licence (CC BY 4.0 listed for the record) | ⏳ |
| IA.3 | Saraga 1.5 is NC (BY-NC vs BY-NC-SA contradictory): no commercial training; internal evaluation needs the owner/legal view or MTG permission | 👤 |
| IA.4 | E2: PANNs **CNN10** (5.2 M params; never tested — our "PANNs" was CNN14) on the existing bench | ⏳ within approved research scope |
| IA.5 | E1: first **real Indian-domain** numbers (Sanidha, session-disjoint; stem-derived activity labels, human spot-checked) | ⏳ after IA.1 |
| IA.6 | Taxonomy v3 (voice family, Western percussion split, banjo/tuba/arpeggiator, difficult pairs, per-class status); `taxonomy.json` unchanged until approved | 👤 approve |
| IA.7 | Annotation schema extension (role, `instrument_id`/`family_id`, `audibility` direct/inferred/uncertain, multi-annotator, disputed, provenance) | 👤 approve |
| IA.8 | Gates: none measurable on real Indian audio today (NOT EVALUABLE); no class is Tier 1 | ✅ recorded |
| IA.9 | **Sound-palette addendum** ([`TONEPILOT_SOUND_PALETTE_RESEARCH.md`](TONEPILOT_SOUND_PALETTE_RESEARCH.md)): six output dimensions:<br>• identity;<br>• source type;<br>• character;<br>• likely processing;<br>• role;<br>• timing.<br>Sound design is a non-instrument family. Composer evidence matrix (first pass: thin; Kolaveri Di is the strongest per-song record). Sound Character Dataset audit:<br>• NSynth qualities CC BY 4.0;<br>• E-GMD CC BY 4.0;<br>• IDMT effects is NC-ND (rejected);<br>• self-applied effects on permissive dry audio give exact labels. | ✅ researched; 👤 approve |
| IA.10 | Benchmarks S1 (NSynth character head) and S2 (self-applied processing head) are runnable now on CPU | ⏳ awaiting approval |
| IA.11 | **E2 CNN10: done** (run 41386940981). CNN10 does **not** replace C:<br>• DEV coverage 60% vs 73%;<br>• NSynth coverage 24% vs 50%;<br>• layered F1 0.28 vs 0.35;<br>• 4.5× slower on CPU.<br>EfficientAT + C stays official. Synthetic/NSynth only. | ✅ measured (synthetic) |
| IA.12 | **Sound-palette coverage and data plan** ([`benchmark/SOUND_PALETTE_COVERAGE_AND_DATA_PLAN.md`](benchmark/SOUND_PALETTE_COVERAGE_AND_DATA_PLAN.md)). 165 terms audited:<br>• 41 existing ids;<br>• 12 aliases + 1 variant;<br>• 11 kept from v3;<br>• **24 new identities (all unsupported)**;<br>• 19 needs-review;<br>• 57 moved to other dimensions.<br>5 claims promoted to documented (secondary); 3 claims not found. | ✅ researched; 👤 approve |
| IA.13 | **Owner recording programme:**<br>• harmonium → bansuri → shehnai/nadaswaram → sitar → santoor → sarangi → dhol/thavil/kanjira → Tamil folk drums;<br>• ≥ 3 performers each before training;<br>• Casio imitation pairs, labelled `imitation`. | 👤 |
| IA.14 | v2 id `kuzhal` is ambiguous (Tamil flute vs Kerala double reed) | 👤 decide |
| TR.1 | **Tone recreation proposal** ([`research/TONEPILOT_TONE_RECREATION_PROPOSAL.md`](research/TONEPILOT_TONE_RECREATION_PROPOSAL.md)):<br>• instrument match (A) and perceptual tone match (B) side by side; A never restricts B;<br>• whole-library nearest-sound search (T1);<br>• fit the tone's envelope, filter and vibrato to the part (T3);<br>• two-tone layers (T3b, restored);<br>• Casio tones as extra candidates (T6).<br>TonePilot's own recreation comes first. | 🔨 T1 in progress |
| TR.2 | **No manual recording** (owner, 2 Nov). Casio tones by name mapping only; optional automatic MIDI-out capture later. Reference library built automatically: [`benchmark/OPEN_SOURCE_TONE_REFERENCE_EXPANSION_PLAN.md`](benchmark/OPEN_SOURCE_TONE_REFERENCE_EXPANSION_PLAN.md):<br>• GO: E-4 (frozen embeddings) → renders + TinySOL/NSynth → E-5 learned cross-source similarity → sealed TEST (Iowa MIS + TinySOL fold 4);<br>• NO-GO: CLAP on the phone, matcher change before E-5 wins. | 📋 plan; ⏳ E-4 next |
| TR.3 | A new sealed TEST sound bank (verified licence) for the next tone-method decision; FluidR3 used once per method on 2 Nov | ⏳ |
| TR.4 | **Real-instrument tone library** ([`research/TONEPILOT_TONE_LIBRARY_SOURCES.md`](research/TONEPILOT_TONE_LIBRARY_SOURCES.md)):<br>• VSCO 2 CE + VCSL (both **CC0**, verified): real strings, woodwinds, brass, harp, pianos, mallets;<br>• SFZ import or CI conversion;<br>• per-instrument download packs;<br>• each new tone must beat the GM tone in the bench and the owner's listening check.<br>Casio/Yamaha factory samples are not usable (proprietary). | 📋 proposal |
| TR.5 | Iowa MIS real recordings as a **sealed real-recording TEST** for tone recreation (evaluation only, never shipped) | ⏳ |

## R. Product and competitor research (Phase A, 2 Nov) — **proposals awaiting owner review, not approved**

Documents:
- [`research/TONEPILOT_COMPETITOR_RESEARCH.md`](research/TONEPILOT_COMPETITOR_RESEARCH.md)
- [`research/TONEPILOT_PRODUCT_GAP_ANALYSIS.md`](research/TONEPILOT_PRODUCT_GAP_ANALYSIS.md)
- [`research/TONEPILOT_PRODUCT_ROADMAP.md`](research/TONEPILOT_PRODUCT_ROADMAP.md)

| # | Item | Status |
|---|---|---|
| R.1 | Findings, from public information only (web-search evidence; direct fetches blocked; no hands-on testing):<br>• analysis (stems, chords, BPM) is commodity;<br>• the documented white space is a song-specific left-hand pattern + matched tones on a Casio CT-X;<br>• Casio's own app supports CT-S/LK-S only;<br>• Yamaha Chord Tracker already does phone-to-keyboard (not our innovation) | ✅ researched |
| R.2 | Proposed M1, "Play this song on my Casio": workspace lanes → tone per section → melody + Live Song Arpeggio over the separated backing (accompaniment approach E, hybrid) | 👤 owner review |
| R.3 | Owner hands-on competitor test with lawful audio (protocol in the research doc §7) | 👤 |
| R.4 | Contradictions to resolve:<br>• `CAPABILITIES.md` is stale (118 vs 224 tests);<br>• "instrument recognition secondary" (memory §1) vs "main differentiation" (new brief) | 👤 |

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
| 3.4 | Proxy benchmark A vs C (run 41315008400): off-the-shelf labels unusable (Apple 94% unknown); **C · EfficientAT + head leads: 59% exact, 75% family, layered window F1 0.37**; ~25% confident wrong family. See `docs/benchmark/INSTRUMENT_PROXY_RESULTS.md` | 🧪 |
| 3.4b | **Gate 1 calibration v1** (run 41321228828): ≤5% met on DEV but **not on TEST** (C·EfficientAT: coverage 99%, wrong family 26%). Cause: DEV came from the same sound bank as TRAIN, so the heads were over-confident. Coverage curve on TEST: 88% family accuracy at 70% coverage, 94% at 50%. Source type: imitation tones mostly read as acoustic (8/36) | 🧪 (finding) |
| 3.4c | **Gate 1 v2**: with NSynth as cross-domain DEV, **≤5% wrong family met on TEST** (EfficientAT + head: 41% coverage, 3% wrong, 94% selective) for clean/reverb/compressed; **fails on 1 s clips** (25% wrong); **poor on NSynth-test (real notes)** → GM-only training does not transfer | 🧪 |
| 3.4e | **Gate 1 v3** (+ NSynth-train): real-note generalisation 33% → **87%** selective (NSynth-test, 47% coverage, 6% wrong); synthetic set now 17% wrong (one threshold can't fit two domains) | 🧪 |
| 3.4f | **Gate 1 v4** (run 41328362434): synthesised imitations help family accuracy (imitation wrong-family 49%→22%, clean 17%→10%); source head recognises about half of imitations (31/60; an earlier "never" claim was a truncated-log error); short-clip thresholds fail on DEV; Apple job still crashes (fix committed) | ✅ measured (synthetic). v4b: "heads must agree" fixes 1 s clips on synthetic (25%→7% wrong) but hurts real NSynth (7%→9%, 87%→61%); DEV still selects plain C |
| 3.4d | Source-type head improvement (imitation vs acoustic) and hybrid sounds | ⏳ |
| 3.5 | Add NSynth real-sample set (families, acoustic/electronic/synthetic) to the benchmark | ⏳ |
| 3.6 | Add licensed real recordings (GuitarSet, Saraga, CC clips) | ⏳ (needs 2.6) |
| 3.7 | Fine-tuning experiment (B), only if C leaves a measured gap; resumable on free Colab/Kaggle | ⏳ (approval for large training: 👤) |
| 3.8 | Five-stage analyser prototype (content → family → instrument → time aggregation → tone mapping), Core ML, shadow mode | ⏳ (approval: 👤) |
| G2.1 | **Gate 2 Core ML** (run 41323484719, macos-26): fp16 9.9 MB, 99.5% family-decision agreement, ~4 ms/window (Mac); int8 5.1 MB 97.2%; 6-bit rejected (87.2%). `docs/benchmark/COREML_DEPLOYMENT_REPORT.md` | 🧪 Mac measured |
| G2.2 | Swift EfficientAT mel front-end: **matches PyTorch (2.2e-5)** on Linux and macOS; **Accelerate vDSP path: 0.12 s per 4-min song** (Mac runner; portable path 2.5 s on Linux) | ✅ tested (Mac/Linux); iPhone via Lab |
| G2.3 | **TonePilot Lab**: separate iPhone benchmark app (main app untouched). Measures:<br>• cold and warm latency per compute unit (median, p90, p95);<br>• full-song time for 1/3/4/5 min, 3 repeats each with median and p90 on a full run;<br>• OS-ledger peak footprint, thermal state, battery before and after;<br>• on-device numerics → JSON report.<br>Reports from a simulator are labelled SIMULATED. Rebuilt 2 Nov: run 41340171940, artifact `TonePilotLab-ipa` | 🔨 built; **physical-iPhone measurements pending** |
| G2.4 | **Physical iPhone run** of TonePilot Lab (sideload, press Full run, share the JSON) | 👤 (one session) |
| G2.5 | **Developer-only shadow mode** in the main app:<br>• off by default; runs only when `shadow-enabled`, `efficientat_head.json` and the fp16 model are placed in Documents/Developer;<br>• runs after the production result is final and writes only `Documents/Developer/shadow/*.json`;<br>• songs, arrangements and the UI are unchanged.<br>Core comparison code: `Instruments/ShadowInstruments.swift`, 6 tests. Speed budget: 2.42 s per 4-min song for front-end + head (Linux, no Core ML). The head JSON is exported by the calibration workflow | 🔨 implemented; full build pending; on-device validation pending (G2.4) |
| G2.6 | **Launch gate: median of 5** (limit 4 s; every timing, mean and p90, runner info, history on `ci/launch-history`). Also fixes the peak-memory gate, which never matched Xcode's metric name. Control comparison workflow `launch-control.yml` (v0.3.71 vs main, same runner class) | 🔨 implemented; awaiting runs |
| 3.4g | **Gate 1 decision (owner, 2 Nov):**<br>• plain C stays official;<br>• C-agree not adopted;<br>• no more threshold-only variants without new DEV data;<br>• next lever is licensed real recordings (Indian instruments, acoustic vs imitation pairs);<br>• 5% wrong-family target **not yet met on all conditions** | ✅ decided |
| 3.9 | Real-song evaluation per language with verified annotations | 📝 |
| 3.10a | **Wikimedia Commons survey** (metadata only, branch `research/indian-audio`): eligible (CC0/PD/CC BY) candidates: tabla 21, veena 28, viola 17, dholak 10, mridangam 1, thavil 1, nadaswaram 1; **none** for ghatam, dhol, bansuri, shehnai, sitar, santoor, tanpura, sarangi, harmonium. Search hits are UNVERIFIED (some are not the instrument; some licences are uploader claims on old recordings) | 🧪 survey done; listening verification 👤/⏳ |
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
| 4.1b | **Stage-5 tone map** (`taxonomy.json` → `tone_map`): 53 instruments → candidate TonePilot tones, validated against the tone library (`InstrumentToneMapTests`) | ✅ tested |
| 4.3 | Indian tones from licensed samples or synthesis (bansuri, nadaswaram, veena, santoor, …) to replace or improve the "-like" GM variants. **No tone at all yet for tabla, mridangam, dholak, ghatam, kanjira, thavil, dhol, electronic percussion, frame drums, ambient/hybrid textures** | ⏳ |
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
| F.4 | Model size, memory, inference speed and battery benchmarks (CI + iPhone/Android) | 🔨 CPU speed + parameters in the benchmark; **EfficientAT Core ML** (run 41317441310): fp32 19.6 MB / 7.2 ms per 1 s window, fp16 9.9 MB / 4.5 ms (Mac runner, all units), matches PyTorch (3e-7 fp32, 4e-4 fp16). On-iPhone timing and battery ⏳ |
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
