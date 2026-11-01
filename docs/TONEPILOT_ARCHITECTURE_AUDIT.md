# TonePilot — Architecture Audit

**Date:** 1 November 2026 · **Code audited:** `main` at `91a92c5` (v0.3.71) · **Scope:** Phase 0, no production code changed.

**Bottom line:** live playing, the sound engine, the mixer, recording and the build gates are solid. The weak part is *listening*, and the measured weak points are tone matching (4 of 12 leads exactly right), beat grids in songs without drums (beat F 0.52), time signature (10 of 24), and chords in minor keys (25–44% of bars). The arpeggio learner itself is strong: **given correct beats and chords it learns the pattern 100% right** — its real-world errors come from those upstream inputs. There is also a licensing risk in what ships today: the Demucs separation weights are not cleared for commercial use.

How to read the evidence labels used in every TonePilot audit document:

| Label | Meaning |
|---|---|
| **Measured** | Run during this audit (see "Baseline measurements"); reproducible |
| **CI** | Reported by the GitHub Actions build of v0.3.71 |
| **Source** | Read from an official repository or model page (linked) |
| **Estimate** | Engineering judgement, not measured |
| **Unknown** | Not established; how to find out is stated |

---

## 1. What the product is, as built

- iOS app (SwiftUI, 8 052 lines in `App/Sources`) over the shared Swift package **TonePilotCore** (10 991 lines), plus an Android app (Kotlin/Compose) that calls the same core through a C bridge (`TonePilotBridge/CAPI.swift`, `AppCore.swift`, `android/app/src/main/cpp/tonepilot_jni.c`).
- 178 core tests (`swift test`, Linux and macOS), an iPhone-simulator speed and crash test, and a Core ML conversion workflow with a separation quality gate.

## 2. Module-by-module status

| Area | Files | Status | Evidence | Notes |
|---|---|---|---|---|
| USB-MIDI input, routing | `MIDIInputManager`, `MIDIMessage`, `NoteRouter` | **Works** | 16 MIDI tests, stuck-note tests | Router releases exactly what it started |
| Sound engine | `ToneEngine`, `DSP`, `SoundFont`, `Instrument`, `EngineController` | **Works** | Engine tests; CI: 3.5% of real time at 37 voices | Sampler + synth (7-voice unison), filter envelope, drive, effects |
| Mono/legato safety | `ToneEngine` | **Works (fixed v0.3.70)** | `MonoSafetyTests` fail on old code, pass now | Stale held-key lists caused stuck notes |
| Live fill | `LiveFill`, `LiveArpeggiator` | **Works (fixed v0.3.71)** | `LiveFillTests` hang on old lock design, pass now | Needs owner confirmation on the Casio |
| Recording | `Recorder`, `Mp3Encoder` + LAME | **Works** | CI MP3 check | |
| Separation | `StemSeparator`, `CoreMLNetwork`, `Native/CDemucs`, `coreml-convert.yml` | **Works technically; licence risk** | CI gate (Core ML within 0.5 dB of C++ per part) | See §5 |
| Lead/Backing split | `LeadSplitter` (+ `LeadTracker`) | **Works** | CI: 4.6 s per 4-min song; exact sum | DSP harmonic masks |
| Tempo and beats | `TempoAnalyzer` | **Incomplete** | Measured: beat F 0.92 with drums, 0.52 without; 6 of 24 half/double/×1.5 errors | Ellis 2007 DP tracker on one onset envelope |
| Time signature / downbeats | `SectionInsights.timeSignature`, `ArpeggioLearner.downbeatPhase` | **Inaccurate** | Measured: 10 of 24 right; 3/4 and 6/8 mostly read as 4/4 | Two separate downbeat heuristics (duplicated logic) |
| Key and chords | `HarmonyAnalyzer` | **Incomplete** | Measured: 70% of bars exact, 78% right root; minor-key songs 25–44%, keys wrong | KK key profiles, 24 triad templates, Viterbi |
| Sections | `StructureAnalyzer`, `SongAnalyzer.relabelInstrumentalSections` | **Boundaries work; grouping and labels weak** | Measured: boundaries 4/4; repeats grouped ABCBD instead of ABABC; labels without vocals all intro/interlude/outro | Foote novelty + SSM; labels are rules |
| Melody | `MelodyExtractor` | **Prototype-quality, untested on real singing** | No real-vocal benchmark exists | Melodia-style DSP; keeps pitch bends (good) |
| Instrument recognition | `App/Audio/InstrumentRecognizer` (Apple SoundAnalysis) + `InstrumentEvidence` | **Prototype** | CI: 14 of 19 clean GM instruments (74%); keyword label mapping | iOS only; no Android equivalent |
| Tone matching | `ToneMatcher`, `PartMatcher` | **Prototype, inaccurate** | Measured: lead 4/12 exact sound, 7/12 family; backing 2/12 exact, 5/12 family | Earlier 95–99% figures were self-graded (same measure chose and graded) |
| AI arranger | `AutoArranger`, `ToneIntensity` | **Works as rules; policy gaps** | Unit tests | Right hand uses the background part's match even in sung sections |
| Arpeggio learning | `ArpeggioLearner`, `ArpeggioStyles`, `SongArpeggio` | **Works when inputs are right** | Measured: 100% chord degrees, step F 1.00 with true beats/chords; grid chosen 16ths for 8th-note patterns (harmless, but wasteful) | Real songs inherit beat/chord errors |
| Model download | `ModelStore`, `ModelArchive` | **Works** | Size + SHA-256 manifest | |
| Storage | `LibraryStore`, `Song`, `Library` | **Works** | Persistence tests | Optional fields keep old data readable |
| Optional server | `server/` (Python, Demucs + Basic Pitch) | **Works, rarely used** | 8 Python tests | Off the product's main path |

## 3. Android parity

Android shares TonePilotCore but **not** these iOS-only parts: separation (Core ML + `Native/CDemucs` are linked only into the iOS target; no stem code in the Android app), Apple instrument recognition, the MP3 Record tab (Android records only for Listen mode), and Song Arpeggio / live fill (no references in `AppCore.swift`). Android today is analysis-from-mix plus tones and playing. Any new model must have a non-Apple path (ONNX Runtime or TFLite) or Android falls further behind.

## 4. Duplication and unnecessary complexity

1. **Two app orchestrators**: `AppModel.swift` (990 lines, iOS) and `AppCore.swift` (968 lines, Android bridge) both run the import → analyse → arrange flow. Moving orchestration into TonePilotCore would make every pipeline change land once.
2. **Two downbeat/meter heuristics**: `SectionInsights.timeSignature` and `ArpeggioLearner.downbeatPhase` estimate the same thing differently, and neither is reliable (10/24).
3. **Two pitch trackers**: `MelodyExtractor` and `LeadTracker` (inside `LeadSplitter`) solve overlapping problems with separate code.
4. **Two tone-choice paths**: `AutoArranger.rankLeads` (rule ranking) and `PartMatcher` (measured match) compete; the arranger picks a winner by a threshold rather than combining evidence.
5. **Static data in code**: `FactoryPatches.swift` (601 lines) holds the tone library as Swift literals; a JSON resource would let tones be added and tested without recompiling.

## 5. Licensing findings in what ships today

| Dependency | Ships? | Code | Weights / data | Status under the owner's rules |
|---|---|---|---|---|
| Demucs `htdemucs` | Yes (in-app download) | MIT | The Demucs README says **"The license of the weights is not clear"** ([source](https://github.com/adefossez/demucs)); its MUSDB18-HQ training data is licensed **"other-nc"** on Zenodo record 3338373 (confirmed by the CI scan, `docs/research/model_scan.md`) | **FREE BUT UNVERIFIED (non-commercial training data) — do not ship commercially** |
| Demucs `htdemucs_6s` | Yes (in-app download) | MIT | Trained only on a Meta internal dataset; README: a CC-NC-BY licence **"likely"** applies ([source](https://github.com/adefossez/demucs)) | **FREE BUT RESTRICTED (likely non-commercial)** |
| demucs.cpp, Eigen | Yes | MIT, MPL-2.0 | — | Safe |
| GeneralUser GS | Yes | — | "use … without restriction for your own music creation, private or commercial"; "use it in your software projects"; silent on ML training; author cannot verify every sample's origin ([source](https://github.com/mrbumpy409/GeneralUser-GS/blob/main/documentation/LICENSE.txt)) | Safe for playback; **training use unaddressed** |
| LAME 3.100 | Yes | LGPL | — | Safe with LGPL obligations (dynamic linking or relinkable objects) |
| Apple SoundAnalysis, Core ML | Yes | Apple SDK | — | Safe |
| Spotify Basic Pitch | Server only | Apache-2.0 | Weights live inside the Apache-2.0 repository, no separate terms ([source](https://github.com/spotify/basic-pitch)) | Safe (training-data provenance noted in the research doc) |

The 1 November architecture document listed Demucs as "MIT"; that is true of the code only. For personal sideloaded use this is low risk; **before any paid or store release the separation weights need written permission, a replacement with clear rights, or our own model trained on licensed data.**

## 6. Baseline measurements (this audit)

Method: songs rendered from the GeneralUser GS SoundFont with known instruments, notes, beats, chords and sections, run through the current TonePilotCore in release mode (Docker `swift:6.0-noble`, x86-64). Separation is imitated by mixing 10–20% of the other parts into each stem. Benchmark code is kept out of the repository for now (scratchpad) and is proposed as the Phase 2 harness. Synthetic audio is easier than real recordings, so **real-world numbers will be equal or worse**.

| Task | Test set | Result |
|---|---|---|
| Tone matching, lead part | 12 GM lead instruments over strings/pad, choir and bass leakage | **4/12 exact sound, 7/12 right family** |
| Tone matching, backing part | Same 12 songs | **2/12 exact, 5/12 family** |
| Tempo | 24 songs: 72/96/128/150 BPM × 4/4, 3/4, 6/8 × with/without drums | **18/24 within 4%**; 6 half/double/×1.5 errors |
| Beat tracking (F-measure, ±70 ms) | Same 24 | **0.72 overall; 0.92 with drums; 0.52 without drums** (3/4 and 6/8 without drums: 0.03–0.08, beats off-phase) |
| Time signature | Same 24 | **10/24** |
| Chords (per bar, root + major/minor) | 6 songs: triads, minor key, sevenths, inversions, with/without drums | **70% exact, 78% right root**; triads 100%, minor key 25–44%, sevenths and inversions 75% |
| Section boundaries (±2 beats) | A-B-A-B-C song, clear instrument changes | **F 1.00**; repeat grouping **ABCBD** (truth ABABC); labels intro/interlude ×3/outro (no vocals) |
| Arpeggio pattern learning | 5 patterns (16ths, 8ths, tisra 6/8, 3/4, syncopated 3-3-2), true beats and chords supplied | **Step F 1.00, chord degrees 100%**; grid right 2/5 (chose 16ths for 8th-note patterns, harmless) |
| Instrument recognition (Apple) | 19 clean GM instruments (CI) | **14/19 (74%)** |

## 7. Product-policy findings (no model needed)

1. **Right-hand tone in sung sections** uses the background part's match; it should follow the melody in vocal sections and the instrumental hook in interludes.
2. **"Guess 21%" badge** is section-label confidence but reads as tone quality; relabel it and show tone match separately.
3. **Live fill never invents a third?** — `ArpeggioRenderer` plays root-and-fifth when a song chord is uncertain, but `LiveArpeggiator.plan` always plays a third from `songQuality`/memory even when that evidence is weak. It should fall back to no-third voicings below a confidence threshold.
4. **Live fill keeps playing to the chord's end** after the player stops; a "stop after one silent step-cycle" option matches the product requirement "stop cleanly when the player stops".
5. **Pattern validation UI** exists in part (preview, tap-to-correct steps) but has no A/B against the original separated part.

## 8. What to keep, improve, replace

| Keep as is | Improve without replacing | Replace eventually |
|---|---|---|
| ToneEngine, MIDI, NoteRouter, Record, Song Studio, model download, CI gates, LeadSplitter, ArpeggioLearner core | HarmonyAnalyzer (minor keys, bass-aware chroma), StructureAnalyzer (repeat grouping, vocal-aware labels, confidence tiers), ToneMatcher method (multi-pitch, independent grading), arranger policy, live-fill third rule | TempoAnalyzer beat/downbeat stage (by a specialist model if it measures better), tone/instrument evidence (by one small licensed model), Demucs weights (for commercial release only) |

Details and evidence: `TONEPILOT_AI_MODEL_RESEARCH.md`, `TONEPILOT_RECOMMENDED_ARCHITECTURE.md`, `TONEPILOT_BENCHMARK_PLAN.md`.
