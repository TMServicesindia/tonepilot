# TonePilot — Product Roadmap proposal (Phase A → for owner review)

**Date:** 2 November 2026. **Status: proposal only.** Nothing here is approved for implementation. It changes no existing decision, model selection or benchmark result.

Rules carried over:
- iPhone first; Core ML and physical-iPhone validation before any Android work;
- zero budget;
- no new model training because a competitor has a proprietary model;
- no replacing working features without benchmark evidence;
- synthetic results are never presented as real film-song accuracy.

Effort is relative (S / M / L). No calendar dates are given: there isn't enough evidence for them.

## 1. Proposed first complete milestone (the owner's recommendation, refined)

> **M1: "Play this song on my Casio".**
> Import → sections and instrument lanes → matching tone per section → right-hand melody guide + left-hand Live Song Arpeggio, against the original separated backing.

Almost every part exists; M1 is mostly **integration and validation**, not new research. It is the smallest version that does something Moises doesn't document: *your* left-hand chords drive *the song's own* accompaniment figure, in time with the song, through a tone chosen for its instruments.

## 2. Milestones by priority

### P0 — foundational and blocking

| ID | Milestone | User value | Competitor reference | Existing in TonePilot | Required changes | Dependencies | Risk | Free/OSS options | Licence risk | Tests / acceptance | iPhone validation | Effort |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| P0.1 | **Hardware truth on the CT-X870IN** | Everything else rests on it | Yamaha Chord Tracker (phone–keyboard) | USB-MIDI in, audio-out path, `HARDWARE_TEST_CHECKLIST.md` | None (test session) | Owner + Casio | Medium (unknown Local Control, controllers, latency) | — | — | Checklist complete: notes/velocity/sustain received, Local Control behaviour, audio-in latency measured | Owner's iPhone 15 + Casio | S |
| P0.2 | **Physical-iPhone evidence (Gate 2, G2.4)** | Speed and battery trust | — | TonePilot Lab built (run 41340171940) | None (owner runs it) | Sideload | Low | — | — | JSON report: cold/warm latency, 1/3/4/5-min times, peak memory, thermal, battery | Required | S |
| P0.3 | **Launch gate passes on the median of 5** | Publishable builds | — | Implemented 2 Nov | Fix the publish 403 (owner setting) | Runner capacity | Low | — | — | Median ≤ 4 s, all timings reported; control comparison recorded | Simulator (CI) | S |
| P0.4 | **Real-song ground-truth set v1** (Gate 3 start) | Any honest accuracy claim | Steminize's "60–75%" honesty | Annotation schema + validator; 20-song catalogue (metadata) | Owner recordings and annotations; pre-fill tool (TODO B.2) | Legal check for film audio | High (legal, effort) | Commons-licensed Indian instrument clips (verified) | High for film recordings: legal check | ≥ 20 verified annotated items; splits by song identity; per-language counts reported | — | M |

### P1 — essential product capabilities

| ID | Milestone | User value | Competitor reference | Existing | Required changes | Dependencies | Risk | Free/OSS | Licence | Acceptance | iPhone | Effort |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| P1.1 | **Workspace lanes:** chords, beats, sections and instrument lanes (family / unknown + confidence) in Song Studio | See the song at a glance | Moises (sections), Steminize (chord timeline), BandLab (track rows) | Timeline, sections, stems | New lanes (fixed frames; LiveState rule); stress-test identifiers | Production recognizer output | Low–medium | — | — | No layout shift while playing; stress test covers the lanes; launch gate unchanged | Smoothness on device | M |
| P1.2 | **Correction-first editing:** chord, boundary and instrument label | Fix what AI gets wrong | OtoTheory, Steminize, Moises | Section editor sheet | Chord and instrument correction; corrections stored separately as "user truth" | P1.1 | Low | — | — | Corrections persist and survive re-analysis; never fed to training without the owner's approval | — | M |
| P1.3 | **Upstream accuracy on real songs:** beats without drums, minor-key chords | Better patterns everywhere | Chord AI, Moises (both claim beat/downbeat) | DP beats; harmony hypotheses (core); Beat This! evaluated | Benchmark BTC and All-In-One on P0.4 data; adopt only on measured gain | P0.4 | Medium | Beat This! (MIT), BTC (MIT), All-In-One (MIT) | Low | Measured gain on real DEV, confirmed on TEST; no regression on synthetic | Speed budget on device | M |
| P1.4 | **Melody mode polish** (octave/register hint, loop, speed) | Right-hand value now | Muse Forge (piano reduction), Yamaha (melody suppressor) | Melody guide (protected) | Small UI additions only | — | Low | — | — | Melody Player unchanged for existing users (protected); new hints optional | — | S |
| P1.5 | **Separation licence path** | A public release becomes possible | All competitors (proprietary) | Demucs, personal only | Owner sends the drafted permission email, or evaluate licence-clean alternatives | Owner approval | High | To be researched (licence-clean weights) | **High** | Licence register updated; quality ≥ current engine per part (`coreml-convert.yml` gate) | Speed and memory on device | M |

### P2 — differentiating capabilities

| ID | Milestone | User value | Competitor reference | Existing | Required changes | Dependencies | Risk | Free/OSS | Licence | Acceptance | iPhone | Effort |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| P2.1 | **Chords and Arpeggio mode** (M1 core): root–5th–root coaching, assist/manual/auto, independent backing/bass/drum levels | **The headline feature** | OtoTheory (grooves), Yamaha (styles), both generic | Live fill v3, ArpeggioLearner, AccompanimentClassifier (core) | Wire the no-fill classifier; one mode screen; uncertainty indicator | P0.1, P1.3 | Medium | — | — | False arpeggios = 0 on held-out sets (existing gate); pattern fidelity with *estimated* inputs measured (TODO 6.3); owner listening on Casio | Latency on the owner's Casio | M |
| P2.2 | **Tones per instrument lane** (Instrument Maker A/B against the stem) | "Sounds like the song" | RipX (replacement, desktop) | ToneMatcher, Tone Studio, Film Tone Library | A/B audition UI; honest match labels (not section confidence); missing Indian percussion tones (TODO 4.3) | P1.1 | Medium (the owner found the current matching poor) | GeneralUser GS (cleared), own synthesis | Low | Blind A/B by the owner on ≥ 10 sections; no "match %" shown without a validated meaning | — | M |
| P2.3 | **Instrument Analyser v1 in production** | Instrument lanes with Indian instruments | Nobody documents this | Shadow mode (developer-only) | Only after Gate 1 is met on **real** DEV/TEST and Gate 2 on device | P0.2, P0.4 | High (domain generalisation) | EfficientAT (MIT) + own head | Low | ≤ 5% wrong-family on real TEST at stated coverage; per-language report | Full-song time and memory on device | L |
| P2.4 | **Live Song Arpeggio: beat-synced with the song playing** | Perform over the original | Yamaha (keyboard styles follow chords) | Live fill follows chords; song-position sync partial | Tie the pattern phase to the song's beat grid during playback | P1.3 | Medium | — | — | Onsets within ±30 ms of the beat grid (measured), stops correctly on silence, full chord or section end | Latency on device | M |

### P3 — advanced (only after M1 is validated)

| ID | Milestone | Note |
|---|---|---|
| P3.1 | Multi-instrument figure reconstruction (counter-melodies, interlude riffs) as playable parts | Approach D; needs reliable note events per stem (Basic Pitch where it measures better) |
| P3.2 | MIDI output (to the Casio or as file export) | Only if the owner needs it. The Casio can play its own voices from MIDI, but TonePilot's value is its own tones |
| P3.3 | Source-type head (acoustic vs imitation) | Needs real acoustic/imitation recording pairs (Gate 1 v4 finding) |
| P3.4 | Android parity | **Not approved.** Only after iPhone validation and explicit approval |

## 3. What NOT to build (existing solutions are sufficient)

1. **A better general stem separator.** Moises, BandLab and others compete on this. Reuse open models; improve only for licence reasons (P1.5).
2. **Note-level audio editing / a DAW.** RipX and BandLab do this.
3. **Piano sheet-music transcription and PDF/MusicXML export.** Muse Forge and Piano Transcriptionist do this.
4. **Text-to-music generation.** Off-mission.
5. **A generic groove library.** The Casio already has styles; OtoTheory has grooves. Keep only a rule-based fallback.
6. **Live microphone chord recognition as a headline feature.** Chord AI does it; TonePilot already has Listen Mode for licensed streaming playback.
7. **Phone-to-keyboard connection as "innovation".** Yamaha precedent.

## 4. Real-world evaluation plan (repeatable)

1. **Audio access (legal only):**
   - owner recordings and Casio performances;
   - verified licence-eligible Commons clips (tabla 21, veena 28, viola 17, dholak 10, …);
   - film recordings only after the legal check.
   - Purchase does not grant evaluation or training rights.
2. **Splits:**
   - by song identity: TRAIN / DEV / TEST;
   - the 20-song catalogue (11/4/5) stays out of training and threshold tuning;
   - grow towards ≥ 60 songs.
3. **Annotations (schema `docs/benchmark/annotation.schema.json`):**
   - instrument, role, entry/exit;
   - chords per beat; beats and downbeats; sections;
   - the accompaniment figure per section.
   - AI pre-fill is allowed; human verification is mandatory; a second pass for TEST.
4. **Metrics, per language and per family:**
   - coverage, wrong-family rate, selective accuracy and unknown rate (together);
   - window and track F1;
   - onset/offset error median and p90;
   - chord accuracy per beat; beat F; section boundary F;
   - pattern fidelity (degrees, timing);
   - false-fill rate.
5. **Performance:**
   - full-song processing time on a **physical iPhone** for 1/3/4/5 min, with peak memory;
   - Mac CI numbers labelled as Mac.
6. **Reporting:** every number tagged as one of
   - Measured on Mac CI;
   - Measured on physical iPhone;
   - Estimated;
   - Simulated;
   - Pending.

## 5. Proposed Phase B plan (for owner review — not started)

1. Owner decisions on the five questions:
   - separation;
   - reuse vs develop;
   - the smallest accompaniment;
   - the workspace as the centre;
   - the first "Moises doesn't do this" feature (proposed: P2.1 Chords and Arpeggio mode).
2. Write the M1 product spec:
   - screens, states (including the uncertainty and no-fill states);
   - acceptance criteria per screen;
   - the stress-test additions.
3. Hands-on competitor test with lawful audio (§7 of the research document), done by the owner, with results recorded in the research doc.
4. P0.1 hardware session and P0.2 Lab run (both owner, one session each).
5. Then Phase C: engineering milestones for M1 in the order P1.1 → P2.1 → P2.2 → P2.4, each through the full build gate.
