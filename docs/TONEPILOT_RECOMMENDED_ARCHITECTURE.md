# TonePilot — Recommended Architecture (revision 2)

**Date:** 1 November 2026 · **Status:** for the owner's approval; nothing implemented. Revision 2 adds the owner's Phase 0 review: transcription is one input among several, chords before patterns, rhythmic cycles instead of forced time signatures, accompaniment-type classification, a real-audio dataset, Demucs licensing, and Android parity for every change.

**Product focus:** TonePilot's advantage is understanding a song's **accompaniment** and letting the player recreate it by playing simple chords on the Casio. Most engineering effort goes to the Song Arpeggio chain: rhythm → chords → accompaniment notes → pattern → live fill. Instrument recognition and tone matching are a separate, later programme.

Evidence labels (Measured / Source / Estimate / Unknown) follow `TONEPILOT_ARCHITECTURE_AUDIT.md`; licence classes (SAFE, SAFE\*, RESTRICTED, UNVERIFIED) follow `TONEPILOT_AI_MODEL_RESEARCH.md`.

---

## 1. Principles

1. **Accuracy before model count.** Nothing ships unless it beats the current code on independent data, real audio included.
2. **Shared core, two inference back-ends.** All logic, pre- and post-processing live in TonePilotCore. Each model runs through a small `InferenceBackend` interface: Core ML on iOS, LiteRT (TFLite) or ONNX Runtime on Android. **A model without a working Android back-end is not approved.**
3. **Separate questions, separate tests.** Note transcription, harmony, rhythm, pattern detection, phrase-vs-pattern classification, recognition and tone matching are distinct stages.
4. **Honest confidence.** Every output carries confidence and a "don't know" state; the UI never shows a confident label from weak evidence.
5. **Live playing is protected.** No analysis on the main, MIDI or audio threads; ToneEngine, NoteRouter, Record and Tone Studio are unchanged by this programme.

## 2. Data flow

```
Import (audio the user has rights to)
 │
 ├─ Decode, first analysis (existing)
 ├─ Separation (existing Demucs — personal builds; commercial builds need cleared weights, §5)
 │      vocals · drums · bass · other (+ piano · guitar) → Lead / Backing (existing DSP)
 │
 ├─ R. RHYTHM: beat grid + rhythmic cycle
 │      Beat This! small (activations) ⊕ TempoAnalyzer (tempo cross-check) ⊕ onset subdivision
 │      → beats, downbeats, cycle = {beats per cycle, subdivision 2/3/4, accent pattern, confidence}
 │        conventional label (4/4, 3/4, 6/8…) only when confident; otherwise "cycle of N, unlabelled"
 │
 ├─ H. HARMONY: time-varying chords on the beat grid
 │      bass stem → root · backing/other → bass-free chroma · key-aware HMM (major + minor)
 │      chord changes allowed on any beat (half-bar changes) · 7ths/inversions recognised and
 │      folded for degree mapping · drone/modal detector → "drone" state, never a guessed triad
 │      (BTC model evaluated as an alternative)
 │
 ├─ N. NOTE EVENTS per accompaniment stem
 │      Basic Pitch (evaluated per stem) ⊕ existing onset/harmonic probe (fallback, cross-check)
 │      → onset, offset, pitch, velocity, confidence per note
 │
 ├─ A. ACCOMPANIMENT TYPE per section (new classifier, rules + features)
 │      broken-chord pattern · rhythmic chord pattern (strums/stabs) · sustained pad/chords ·
 │      melodic hook/phrase · bass-line only · none (sparse/solo) → decides what live fill may do
 │
 ├─ P. PATTERN LEARNING (existing ArpeggioLearner, extended — combines R + H + N + A)
 │      notes → chord-relative events: cycle position, degree, octave offset, duration, accent,
 │      register; repeated-bar clustering → main pattern + variations; confidence per event
 │      A/B validation against the original stem before live use
 │
 ├─ L. LIVE FILL (existing LiveArpeggiator + LiveFill, rules tightened)
 │
 └─ T. INSTRUMENTS AND TONES (separate programme, later)
        recognition (what plays) and matching (which TonePilot tone) — CLAP music vs own model
```

## 3. Change register

Each change lists: current implementation · proposed improvement · why · licence · expected benefit · size and device needs · benchmark and acceptance · fallback.

### C1 — Beat grid and downbeats

| Field | Content |
|---|---|
| Current | `TempoAnalyzer`: onset autocorrelation + Ellis DP beats; meter from beat-strength periodicity |
| Proposed | Beat This! small for beat + downbeat activations; fuse with TempoAnalyzer tempo; one shared grid for chords, structure and patterns |
| Why | Measured: beat F 0.52 without drums (0.92 with); 6 of 24 tempo errors were half/double/×1.5 |
| Licence | Beat This! code + weights MIT (README) — **SAFE\*** (training-data note) |
| Expected benefit | Paper reports strong results on many datasets (to be **re-measured**; no figure claimed here). Target: no-drum beat F ≥ 0.85 |
| Size / device | ~8.1 MB; inference on 4-min song **untested**; iOS Core ML + Android LiteRT/ONNX conversions to be proven in CI |
| Benchmark / acceptance | S1 rhythm set (24 + new cases), S2, S4 real audio incl. Indian film-style: beat F, downbeat F, CMLt/AMLt; must beat TempoAnalyzer on S4 and keep added time ≤ 10 s per 4-min song on iPhone 15 |
| Fallback | Feature flag → current TempoAnalyzer |

### C2 — Rhythmic cycle instead of a forced time signature

| Field | Content |
|---|---|
| Current | `SectionInsights.timeSignature` and `ArpeggioLearner.downbeatPhase`: two heuristics, 10/24 correct |
| Proposed | One `RhythmCycle` model in the core: beats per cycle (2–16), subdivision (2, 3, 4), accent pattern (e.g. 3+3+2, 3+2+2 for misra chapu-like 7, 4+4 for 8-beat cycles), confidence. A Western label is shown only when it fits confidently; else "7-beat cycle (3+2+2)" or "cycle unclear" |
| Why | Owner: Indian film rhythms don't always map to 4/4, 3/4, 6/8; forcing a label breaks patterns |
| Licence | Own code — SAFE |
| Expected benefit | Correct pattern length per cycle; fewer wrong-grid patterns (measured grid errors 3/5 even with true beats) |
| Size / device | 0 MB; shared core |
| Benchmark / acceptance | S1 + S5 cases: 4/4, 3/4, 6/8, tisra, 5- and 7-beat cycles, syncopation, rubato intro, tempo change; cycle length right ≥ 85%, subdivision right ≥ 90%, and "unclear" (not a wrong label) on rubato |
| Fallback | Current heuristics |

### C3 — Time-varying, bass- and key-aware chords

| Field | Content |
|---|---|
| Current | `HarmonyAnalyzer`: KK key profiles, 24 triad templates, Viterbi over beats on the full-mix chroma |
| Proposed | Bass stem → root evidence; backing/other stem → chroma without vocals; key-aware transition priors (major and minor keys, relative-key ambiguity kept as alternatives); changes on any beat; seventh/sus/inversion templates folded to a degree map; drone/modal detector (strong sustained pitch class + weak triad fit → "drone on X") |
| Why | Measured: 70% of bars; minor-key songs 25–44% with wrong keys; sevenths/inversions 75%. Wrong chords = wrong thirds in the fill |
| Licence | Own DSP — SAFE. Alternative evaluated: BTC (MIT repository, 12.2 MB) — **SAFE\*** |
| Expected benefit | Target ≥ 85% bar accuracy overall, ≥ 75% minor keys, half-bar changes detected |
| Size / device | 0 MB (DSP) or 12.2 MB (BTC, conversion untested) |
| Benchmark / acceptance | S1 chord set extended (half-bar changes, slash chords, drones), S2 (MIDI-derived chords), S4 real audio: beat-level accuracy, change-time error; BTC adopted only if it beats improved DSP on S4 |
| Fallback | Current analyzer |

### C4 — Accompaniment note events (transcription as one input)

| Field | Content |
|---|---|
| Current | `ArpeggioLearner`: onset envelope on the step grid + harmonic-sum pitch probe at each onset |
| Proposed | Evaluate per stem (piano, guitar, backing, other): (a) existing probe, (b) Basic Pitch notes, (c) both with agreement. Output note events with onset, offset, pitch, velocity, confidence. Heavy transcribers (ByteDance piano, YourMT3) run only offline in CI as reference "upper bounds" |
| Why | The learner needs register, durations and exact chord tones; the probe only finds the strongest new pitch per onset. Owner: Basic Pitch must not be assumed to handle dense film accompaniment |
| Licence | Basic Pitch Apache-2.0 (repo + official HF + LiteRT card) — **SAFE\*** |
| Expected benefit | Unknown until measured; the benchmark reports per-stem note F so the right method can be chosen per stem type |
| Size / device | 0.84 MB LiteRT (Android benchmarks on the card); Core ML conversion listed in README (to measure on iPhone) |
| Benchmark / acceptance | GuitarSet (real guitar, CC BY 4.0), Slakh stems (CC BY 4.0), S1, S3 owner recordings: note F (onset ±50 ms), offset F, octave errors, per stem; Basic Pitch used only for stem types where it beats the probe |
| Fallback | Existing probe (always available) |

### C5 — Accompaniment-type classifier

| Field | Content |
|---|---|
| Current | Learner returns either a step pattern or "sustained" |
| Proposed | Per section: **broken-chord pattern** (repeating chord-tone sequence), **rhythmic chord pattern** (simultaneous chord hits: strums, stabs, comping), **sustained** (pads, held chords), **melodic hook/phrase** (non-repeating or scale-wise lines), **bass line only**, **none** (sparse, solo, rubato). Features: notes per onset (polyphony), cross-bar repetition, chord-tone ratio, step-wise motion ratio, onset density |
| Why | Owner: never force an arpeggio into a hook, solo or passage where it doesn't belong |
| Licence | Own — SAFE |
| Expected benefit | Live fill plays only where the song has a repeatable accompaniment; hooks offered as a hook, not as an arpeggio |
| Size / device | 0 MB |
| Benchmark / acceptance | Labelled sections in S1/S4/S5; type accuracy ≥ 85%; **zero** arpeggios generated in sections labelled hook/solo/none |
| Fallback | Current two-way behaviour |

### C6 — Pattern learning that preserves the song's actual sequence

| Field | Content |
|---|---|
| Current | `ArpeggioPattern`: steps × degrees with velocity and length, one pattern per repeated section group; 100% correct with true beats/chords (measured) |
| Proposed | Learn from note events (C4) on the cycle grid (C2) with chords (C3): event = cycle position, degree, octave offset, duration, accent, register; cluster bars → main pattern + variations (e.g. bar 4 fill); keep the original order of notes (e.g. Root → Fifth → Octave → Third → Fifth → Octave) exactly; per-event confidence; A/B preview against the original stem and a note list; tap-to-correct (exists); approve per section |
| Why | Owner: extract the actual sequence and timing, then map to the player's chord |
| Licence | Own — SAFE |
| Expected benefit | Keep ≥ 90% degree accuracy with **estimated** beats/chords (today's 100% assumes perfect inputs) |
| Size / device | 0 MB |
| Benchmark / acceptance | S1 pattern set with estimated inputs; S3 owner-played patterns; owner approval on 10 real sections; sequence edit distance ≤ 1 event per bar median |
| Fallback | Current learner output |

### C7 — Live fill rules

| Field | Content |
|---|---|
| Current | `LiveArpeggiator` + `LiveFill`: fill after R·5, melody above the split ignored, full chord silent, chord memory, MIDI-thread with separate locks |
| Proposed | (1) Never invent a third: play one only if the player played it, memory holds it, or the song's chord at this moment has confidence ≥ threshold; else root-fifth-octave voicings. (2) Stop after one silent cycle. (3) Use only validated patterns for the current section and its accompaniment type. (4) Mid-bar chord change replans from the next step. (5) MIDI disconnect stops the fill and releases notes (panic path exists) |
| Why | Owner requirements; measured chord errors make invented thirds likely today |
| Licence | Own — SAFE |
| Expected benefit | Fewer wrong notes; clean stops |
| Size / device | 0 MB; < 1 ms per note budget |
| Benchmark / acceptance | Core tests + Casio device checklist: R-5, full chord, melody above split, chord change mid-bar, cable unplug, paused/playing, tempo scale; duplicate-note rate 0, stuck notes 0 |
| Fallback | Current rules |

### C8 — Structure (sections) with confidence tiers

| Field | Content |
|---|---|
| Current | Foote novelty boundaries (measured 4/4), SSM grouping (measured wrong: ABCBD), labels by rules |
| Proposed | Bar-aligned features (C1/C2), key-invariant repeat grouping, vocal presence from the vocals stem for verse/chorus vs interlude, three display states (boundary · predicted type · guess); All-In-One evaluated as an alternative for labels |
| Why | Song Arpeggio learns per repeated section; wrong grouping splits evidence |
| Licence | Own — SAFE; All-In-One weights MIT on the author's HF repo — **SAFE\*** |
| Expected benefit | Correct grouping on repeats; no "Chorus" from loudness alone |
| Size / device | 0 MB, or 1.4 MB/fold (NATTEN conversion feasibility unknown) |
| Benchmark / acceptance | Boundary F ±0.5/±3 s, pairwise grouping F, label accuracy per tier on S1/S4 |
| Fallback | Current analyzer + manual section editor |

### C9 — Instruments and tones (separate programme)

| Field | Content |
|---|---|
| Current | Apple SoundAnalysis (14/19 clean) + hand-built fingerprint matcher (lead 4/12, backing 2/12) |
| Proposed | Two outputs: recognition (what plays, per 3 s window, family level for Indian instruments) and matching (nearest TonePilot tone by embedding similarity, library rendered at 3 registers × 2 velocities, then existing EQ/reverb fit). Engine chosen by benchmark: **LAION-CLAP music (Apache-2.0)** vs **TonePilot Timbre model** trained on NSynth (CC BY 4.0, real samples) + Slakh2100 (CC BY 4.0) + PDMX (CC0) + own recordings, so it learns real instruments, not only our patches |
| Why | Measured weakness; owner wants it after the arpeggio chain |
| Licence | CLAP music SAFE\*; own model SAFE\* (data attribution) |
| Expected benefit | Target Top-3 family-correct ≥ 10/12 leads and ≥ 9/12 backing on S1, better than baseline on S4 |
| Size / device | CLAP audio branch: to measure (full model 776 MB fp32 — too large unless the audio branch is far smaller); own model ≤ 5 MB target |
| Benchmark / acceptance | Macro F1 (recognition), Top-1/Top-3 (matching), owner blind preference ≥ 70% |
| Fallback | Current matcher + Apple prior |

### C10 — Shared pipeline and Android back-end

| Field | Content |
|---|---|
| Current | Import pipeline duplicated in `AppModel` (iOS) and `AppCore` (Android); separation, live fill, Record, recognition are iOS-only |
| Proposed | `SongImportPipeline` in TonePilotCore; `InferenceBackend` protocol (Core ML / LiteRT / ONNX Runtime); live fill wired into `AppCore` (pure core logic, already MIDI-thread safe) |
| Why | Owner: shared-core functionality is a requirement for every feature |
| Licence | ONNX Runtime MIT, LiteRT Apache-2.0 — SAFE |
| Expected benefit | Each feature lands on both platforms |
| Size / device | Runtime libraries on Android (size to measure) |
| Benchmark / acceptance | Same core tests on both; Android build runs the rhythm, chord and pattern stages on a reference song with identical results (tolerance documented) |
| Fallback | Feature hidden on Android until parity passes |

## 4. Real-audio evaluation data (summary)

Synthetic data alone is not accepted as evidence. The benchmark adds: GuitarSet (real guitar, CC BY 4.0), Slakh stems (CC BY 4.0), the owner's own recordings (Casio and played accompaniments in Tamil, Telugu and Hindi film styles), and CC0/CC BY tracks with per-track licence records, all annotated by hand for beats, cycles, chords, sections, accompaniment type and patterns. No claim about Indian film music or instruments is made without results on that set. Details: `TONEPILOT_BENCHMARK_PLAN.md`.

## 5. Demucs licensing and alternatives

| Option | What | Cost | Risk |
|---|---|---|---|
| A. Personal builds only (now) | Keep current Demucs downloads for the owner's own use | 0 | None for personal use |
| B. Ask for permission | Contact Meta / the Demucs author about commercial redistribution of `htdemucs` weights | 0 | May be refused or unanswered |
| C. Own separator | Train an HT-Demucs-style model (MIT code) on Slakh2100 (CC BY 4.0) + PDMX (CC0) + licensed multitracks | Compute time only (CI or owner's Mac) | Quality on real recordings unknown; long project |
| D. No separation in commercial builds | Analyse from the mix; arpeggio quality drops | 0 | Product quality |

Recommendation: A now; start B in Phase 1; evaluate C only if B fails and a commercial release is planned. The commercial build must never silently download the current weights.

## 6. What stays unchanged

ToneEngine, NoteRouter and MIDI, Record, Song Studio mixer, Tone Studio, model download, LeadSplitter, the CI gates, the section editor.
