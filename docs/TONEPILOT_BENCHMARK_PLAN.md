# TonePilot — Benchmark Plan (revision 3)

**Date:** 1 November 2026 · **Purpose:** every change to listening, rhythm, transcription or matching must beat today's measured baseline on **independent** test data before it ships. A model's own similarity score is never its accuracy.

**What exists today:** an audit harness (rendered songs with known answers, GeneralUser GS) produced the baseline below. It becomes the Phase 2 benchmark, extended with real, legally obtained recordings and manual annotations.

---

## 1. Baseline to beat (measured 1 Nov 2026, current code, synthetic set)

| Task | Metric | Baseline |
|---|---|---|
| Tone matching, lead | Top-1 exact sound / family | 4/12 · 7/12 |
| Tone matching, backing | Top-1 exact / family | 2/12 · 5/12 |
| Tempo | Within 4% | 18/24 |
| Beats | F-measure ±70 ms | 0.72 (drums 0.92, no drums 0.52) |
| Meter | Correct beats per bar | 10/24 |
| Chords | Bar accuracy (root + maj/min) | 70% (root 78%) |
| Section boundaries | F ±2 beats | 1.00 (easy case) |
| Repeat grouping | Exact label sequence | wrong (ABCBD vs ABABC) |
| Arpeggio (true beats/chords) | Step F · degree accuracy | 1.00 · 100% |
| Instrument recognition (Apple) | Clean GM instruments | 14/19 |

## 2. Test sets

| Set | Content | Source and rights | Size target | Annotations |
|---|---|---|---|---|
| **S1 Synthetic** (exists) | Songs rendered from GeneralUser GS + TonePilot synths: known instruments, notes, beats, chords, sections; leakage mixed in to imitate separation | Own renders (GeneralUser use for evaluation is music creation; training use needs permission) | 200 songs (scale up from today's 47) | Exact, generated |
| **S2 Slakh2100 multitrack** | Sample-based multitracks with per-instrument stems + MIDI | **Slakh2100, CC BY 4.0** (Zenodo 4599666, slakh.com) — attribution required | 100 songs (test split) | Exact from MIDI |
| **S2b GuitarSet** | Real acoustic guitar (strummed and picked accompaniment) with note annotations | **CC BY 4.0** (`jhartquist/guitarset`, upstream Zenodo) | All 360 excerpts | Exact notes, chords, beats |
| **S2c NSynth (test split)** | Real single notes from 1 006 instruments | **CC BY 4.0** (magenta.tensorflow.org) | Test split | Family, instrument source |
| **S3 Real recordings, owner** | Owner's Casio + app recordings, owner-played Indian film-style accompaniments | Owner's own rights | 30 clips | Manual (notes, chords, patterns) |
| **S4 Real recordings, licensed** | CC0 / CC BY tracks incl. Tamil, Telugu, Hindi film-style, instrumental and international material; no NC licences | Per-track licence recorded in a manifest | 60 tracks | Manual: beats, downbeats, sections, chords, instruments, a melody excerpt, arpeggio patterns for 2 sections |
| **S5 Hard/negative** | Rubato intros, tempo changes, no drums, drones, dense mass songs, solos (where an arpeggio must **not** be forced) | From S3/S4 | 20 clips | Manual |
| **S6 Indian rhythm cycles** | 5-, 7- (3+2+2), 8- and 16-beat cycles, tisra and chatusra subdivisions, owner-played over film-style accompaniment | Owner's own recordings; Carnatic CC BY sets (`monodox/*`, `kaumudi-ai/*`) only after their audio is confirmed to be real recordings | 30 clips | Manual: cycle length, subdivision, accents |

Accompaniment-type labels (broken-chord, rhythmic chord pattern, sustained, hook/phrase, bass-only, none) are added to every S3–S6 section, because the live fill must stay silent where the song has no repeatable accompaniment.

**What may be claimed:** results on S1/S2 are lab results. A claim about Tamil, Telugu or Hindi film music, or Indian instruments, needs S3–S6 results; until then the app and documents say "not yet measured on real film songs".

Rules: no ripped, pirated or YouTube-downloaded audio; benchmark audio is never shipped in the app; a manifest records each file's licence and source.

## 3. Splits and leakage

- Split by **song**, never by clip: all sections, stems and re-renders of a song stay in one split.
- Near-duplicates (covers, remixes, re-renders of the same MIDI) share a group id and stay together.
- Training (Timbre model) uses only S1/S2 train splits; S3–S5 are **test only**.
- Library-tone embeddings are built from TonePilot patches, which never appear as "original recordings" in test songs of the same split.

## 4. Metrics

| Task | Primary metric | Secondary | Tool |
|---|---|---|---|
| Instrument recognition | Macro F1 over families | Per-class precision/recall; family vs exact-instrument accuracy | Own Swift harness |
| Tone matching | Top-1 and Top-3 accuracy against annotated "acceptable tones" | Blind A/B preference by the owner on S3/S4 | Harness + listening sheet |
| Beats | F-measure ±70 ms | CMLt / AMLt (metrical-level tolerant) | `mir_eval` (MIT) in CI, or Swift port |
| Rhythmic cycle | Cycle-length accuracy, subdivision accuracy | Accent-pattern accuracy; "unclear" rate on rubato (should be high) | Own harness |
| Accompaniment type | Section type accuracy | False-arpeggio rate in hook/solo/none sections (must be 0) | Own harness |
| Downbeats | F-measure ±70 ms | Meter accuracy | `mir_eval` |
| Structure | Boundary F ±0.5 s and ±3 s | Pairwise frame F for grouping; label accuracy per tier | `mir_eval` |
| Chords | Bar and frame accuracy (root, maj/min) | Change-time error | `mir_eval` chord module |
| Melody | Note F (onset ±50 ms, pitch ±50 cents) | Raw pitch accuracy, bend preservation | `mir_eval` |
| Accompaniment transcription | Note F (onset ±50 ms) and with offsets | Per-stem results | `mir_eval` |
| Arpeggio pattern | Chord-degree accuracy per event | Step F, timing error (ms), sequence similarity (edit distance) | Own harness |
| Live fill | Completion accuracy vs pattern, duplicate-note rate, latency (note-in → first fill note) | Stuck-note count (must be 0) | Core tests + device test |
| Separation | SDR/SI-SDR per stem (S2) | **Downstream deltas**: recognition, transcription and pattern accuracy with each separator | Harness |

## 5. Methodology

1. Every candidate runs on the same files with the same pre-processing as the current code.
2. Report each metric with the current baseline beside it and the difference; a change ships only if the primary metric improves on S3/S4 (real audio) and does not regress elsewhere by more than the tolerance in §6.
3. Grading uses ground truth only. Tone matching gets a second, human check: the owner rates the top choice on 20 sections blind (original part vs TonePilot tone).
4. Speed and memory are measured on device (iPhone 15) for any model added: time per 4-min song, peak memory, energy (Instruments).
5. Results are stored as CI annotations and a JSON artifact per build.

## 6. Acceptance criteria (revision 3)

All thresholds below are **targets** for approval, not measured results. "Real" means S3 (owner recordings) and S4/S6 (licensed real audio). **S3 and S6 (Tamil, Telugu and Hindi film-style material and Indian rhythmic cycles) are mandatory acceptance data for every stage they apply to; a stage cannot pass on synthetic or Western data alone.**

| Stage | Primary gate (blocks adoption) | Reported separately (must not regress) | Data |
|---|---|---|---|
| Beat evidence (C1) | No-drum beat F ≥ 0.85 (S1) **and** better than TempoAnalyzer on S6 | Downbeat F; CMLt/AMLt; time per 4-min song | S1, S2, **S6** |
| Rhythmic cycle (C2) | Cycle length ≥ 85%, subdivision ≥ 90% (S1 + S6) | **Wrong confident labels ≤ 5%**; "ambiguous/unknown" on ≥ 80% of rubato clips | S1, S5, **S6** |
| Harmony (C3) | Beat-level accuracy ≥ 85% (S1); minor keys ≥ 75%; better than current on real | Half-bar change detection; drone passages labelled drone ≥ 90%; alternatives contain the truth ≥ 95% | S1, S2, S4, **S6** |
| Note events (C4) | Per stem type: Basic Pitch enabled only where note F beats the DSP probe | Offset F; octave errors; time | GuitarSet, Slakh, S1, **S3**, **S6** |
| Accompaniment type (C5) | **False-arpeggio rate = 0** in hook, solo, sparse and sustained sections | Overall accuracy (target ≥ 85%); missed-arpeggio rate; full confusion matrix | S1, S4, S5, **S6** |
| Pattern (C6) | Degree accuracy ≥ 90%, median onset error ≤ 30 ms, median edit distance ≤ 1 event/bar — with **estimated** beats and chords — **and** owner listening approval on 10 real sections. Both required | Duration error; register (octave) accuracy; variation placement ≥ 80% | S1, **S3**, **S6** |
| Live fill (C7) | Duplicate notes 0; stuck notes 0; core decision < 1 ms; note-in to first fill note < 10 ms on device; **owner's CT-X870IN test passed** | Stop modes (immediate, one cycle, configurable) compared on: stop delay (ms), notes played after release, owner preference | Core tests + device checklist |
| Structure (C8) | Exact grouping on the S1 structure set; no "Chorus" without vocal + repetition evidence | Boundary F (±0.5/±3 s); label accuracy per tier | S1, S4, **S6** |
| Instruments/tones (C9) | Top-3 family-correct ≥ 10/12 leads, ≥ 9/12 backing (S1); better than baseline on real; owner blind preference ≥ 70% | Macro F1; per-class recall; Indian instruments family-level only | S1, S2c, S4, **S3** |
| Shared pipeline (C10) | Fixtures identical (or within documented tolerance) on Linux, iOS simulator and Android emulator; pipeline move changes no output | Android runtime size; inference time on a mid-range Android | Fixtures |
| **Protected functionality** | Existing tests + speed & crash stress test green; Melody Player, ToneEngine, NoteRouter, normal playing, Record, Song Studio, Tone Studio unchanged | Launch time, peak memory, engine load | Every phase |
| Speed | Added analysis ≤ 60 s per 4-min song on iPhone 15 (blocks if > 90 s); Android measured and reported | Battery and thermal notes | Device |

**Adoption rule:** a model replaces or augments existing code only if its primary gate passes on real data **and** nothing in "reported separately" regresses beyond the documented tolerance. A model's own confidence or similarity score is never accepted as its accuracy.

## 7. Test cases that must exist

- 4/4, 3/4, 6/8 and tisra at 60–170 BPM, with and without drums; half/double-time ambiguity; a tempo change; a rubato intro.
- Minor-key progressions, sevenths, inversions, slash chords, a modal/drone section.
- Repeated choruses with small variations; a long instrumental interlude; a section with no vocals.
- Arpeggios: 16ths, 8ths, triplets, syncopated 3-3-2, register changes, accents, per-bar variations (bar-4 fills), a section where the accompaniment is a melodic phrase (must not become an arpeggio), rhythmic strum/stab patterns, sustained pads.
- Chords: changes on beat 3 (half-bar), two chords per beat in fast passages, drone sections with no triad.
- Transcription: the same pattern played by piano, guitar, strings and synth stems, to choose the note-event method per stem type.
- Live fill: R-5 input, full chord input (silent), right-hand melody above the split, chord change mid-bar, MIDI unplug mid-note, song paused vs playing, tempo scale change, each stop mode (immediate, one cycle, configurable).
- Pattern validation: cases where the A/B sounds right but one note is in the wrong order or octave (must fail the objective check).
- Protected functionality: Melody Player on/off during live fill, Record while live fill plays, Tone Studio edits while a pattern plays.
- Recognition: each family alone, with leakage, and in a dense mix; Indian-instrument "-like" mappings at family level.
