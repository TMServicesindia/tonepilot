# TonePilot — Decision Summary (revision 2)

**Date:** 1 November 2026 · **For:** the owner's approval before any implementation. Revision 2 includes the owner's Phase 0 review and a Hugging Face / Zenodo licence scan run in CI (`docs/research/model_scan.md`).

**Recommendation:** spend most of the effort on the Song Arpeggio chain — **rhythm → chords → accompaniment notes → pattern → live fill** — because measurements show the arpeggio learner is right when its inputs are right. Candidate models are small and commercially licensed, and each is adopted only if it beats today's code on real audio:

- **Beat This! small** (MIT, ~8 MB) for beats.
- **BTC chords** (MIT, 12 MB) against improved DSP chords.
- **Basic Pitch** (Apache-2.0, 0.84 MB) per stem, against the existing learner.

Instruments and tones come after the live fill is validated on the Casio, choosing between **LAION-CLAP music (now verified Apache-2.0)** and a small TonePilot model trained on **NSynth and Slakh2100 (both CC BY 4.0)**.

Detail: `TONEPILOT_ARCHITECTURE_AUDIT.md` · `TONEPILOT_AI_MODEL_RESEARCH.md` · `TONEPILOT_RECOMMENDED_ARCHITECTURE.md` · `TONEPILOT_BENCHMARK_PLAN.md` · `TONEPILOT_IMPLEMENTATION_ROADMAP.md`.

---

**1. Keep**
- **Live playing:** ToneEngine, MIDI and NoteRouter, LiveFill threading.
- **Studio and tools:** Record, Song Studio, Tone Studio, model download, LeadSplitter, CI gates.
- **Core learner:** ArpeggioLearner (100% chord degrees with correct inputs).
- **Fallback:** TempoAnalyzer, kept as fallback and tempo cross-check.

**2. Improve (no new model)**
- **Chords:** bass-aware, key-aware, changes on any beat, a drone/modal state.
- **Rhythmic cycles** instead of forced time signatures.
- **Accompaniment type per section:** broken-chord, rhythmic, sustained, hook, bass-only or none.
- **Pattern learning:** from note events, keeping variations.
- **Live-fill rules:** no invented thirds; stop after a silent cycle.
- **Structure:** grouping and confidence tiers.
- **Shared pipeline:** moved into the core, with an Android inference back-end.

**3. Replace (only if measured better)**
- The beat/downbeat stage (Beat This!).
- Possibly the chord engine (BTC vs improved DSP).
- Tone and instrument evidence (CLAP music or own model).
- Demucs weights, for commercial builds only.

**4. Best model integrations to test**

| # | Model | Job | Size | Licence (verified at source) |
|---|---|---|---|---|
| 1 | Beat This! small | Beats, downbeats | ~8.1 MB | MIT code and weights (README) |
| 2 | Basic Pitch | Note events per stem | 0.84 MB (LiteRT) | Apache-2.0 (repo, official HF, LiteRT card) |
| 3 | BTC chord model | Chords, comparison | 12.2 MB | MIT (repository) |

Comparisons only: All-In-One (MIT weights by its author, 1.4 MB per fold; conversion hard), LAION-CLAP music (Apache-2.0; size to measure).

**5. Free and commercially safe**
- **Rhythm, chords, notes:** Beat This!, Basic Pitch, BTC, All-In-One weights.
- **Instruments:** LAION-CLAP (`laion/larger_clap_music` Apache-2.0; `lukewys/laion_clap` CC0), PANNs (CC BY 4.0), Microsoft CLAP (MS-PL / CC BY 3.0).
- **Platform and audio:** Apple frameworks, demucs.cpp, Eigen, LAME (LGPL obligations), GeneralUser GS for playback.
- **Training and test data:** NSynth, Slakh2100, GuitarSet (all CC BY 4.0), PDMX synthesized (CC0).
- Items marked * in the research doc carry training-data notes to record before a store release.

**6. Reject**
- **Verified non-commercial:** madmom, Essentia models, MERT, MuQ/MuQ-MuLan, FCPE, Sheet Sage, Open-Unmix UMXL, MUSDB18-HQ, Mridangam stroke data, ccmusic-database.
- **Unverified weights:** MT3, SOME, RMVPE, ChordMini, RoFormer checkpoints, Spleeter, community instrument classifiers.
- **Too large for the phone** (offline reference only): ByteDance piano (172–628 MB), YourMT3 (2.8 GB), AST, Microsoft CLAP.

**7. Improving instrument and tone recognition (later phase)**
- Separate recognition from matching.
- Compare CLAP music against a small own model trained on **real** instrument audio (NSynth samples, Slakh stems, your recordings), not only TonePilot patches.
- Embed library tones at several pitches and velocities.
- Grade against ground truth and your blind listening.
- Indian instruments at family level until licensed recordings exist.

**8. Improving rhythm and structure**
- Beat This! fused with the current tempo analysis.
- A rhythmic cycle (beats per cycle, subdivision, accents, confidence), with a Western label only when it truly fits.
- Structure on the bar grid, with key-invariant repeat grouping and vocal-aware section types.

**9. Improving exact broken-chord extraction**
1. Correct beat grid and cycle.
2. Correct, time-varying chords.
3. Note events per stem, whichever method measures best for that stem.
4. An accompaniment-type gate.
5. Learning the exact note order, register, duration and accents, with variations.
6. A/B validation against the original stem.

Basic Pitch is one input, never the whole answer.

**10. Order**
1. Licensing and benchmark foundation, with real audio.
2. Rhythm.
3. Chords.
4. Accompaniment extraction.
5. Live Song Arpeggio on the Casio.
6. Instruments and tones.
7. Android parity, regression and release.

Android parity is an acceptance item in every phase.

---

**Demucs:** confirmed risk. Its README says the weight licence "is not clear", and its MUSDB18-HQ training data is "other-nc" on Zenodo. The plan:
- Personal builds keep it.
- Ask the Demucs author and Meta for permission in Phase 1.
- Consider our own separator trained on Slakh2100 (CC BY 4.0) only if permission fails and a commercial release is planned.
- A commercial build never silently downloads the current weights.

**Decisions needed from the owner**
1. Approve revision 2 of the roadmap.
2. Approve sending permission requests to the Demucs author/Meta and the GeneralUser GS author (I'll draft both).
3. Agree the gates in `TONEPILOT_BENCHMARK_PLAN.md` §6.
4. Start the owner-recorded clips for the real-audio set: Casio performances and played accompaniments in Tamil, Telugu and Hindi film styles, including Indian rhythmic cycles.
