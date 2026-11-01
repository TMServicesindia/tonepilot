# TonePilot — Decision Summary

**Date:** 1 November 2026 · **For:** the owner's approval before any implementation.

**Recommendation:** at most **three** new models, all small and commercially safe or self-trained, each shipped only after it beats today's measured code: **Beat This! (small, MIT)** for beats and downbeats, **Basic Pitch (Apache-2.0)** for accompaniment notes, and **one TonePilot-trained timbre model** for instruments and tones. Everything else is DSP and music-theory work in the shared core. The measurements show the arpeggio learner already works when its inputs are right, so rhythm and chords come first.

Full detail: `TONEPILOT_ARCHITECTURE_AUDIT.md` · `TONEPILOT_AI_MODEL_RESEARCH.md` · `TONEPILOT_RECOMMENDED_ARCHITECTURE.md` · `TONEPILOT_BENCHMARK_PLAN.md` · `TONEPILOT_IMPLEMENTATION_ROADMAP.md`.

---

**1. What should we keep?**
ToneEngine, MIDI and NoteRouter, Record, Song Studio, model download, LeadSplitter, the CI gates, the section editor, and the ArpeggioLearner core (measured: 100% chord degrees, step F 1.00 when beats and chords are right). Keep `TempoAnalyzer` as a fallback and confidence check.

**2. What should we improve (no new model)?**
- **Chords:** bass-aware, key-aware recognition. Measured 70% of bars; minor keys 25–44%.
- **Structure:** key-invariant repeat grouping and vocal-aware labels with confidence tiers. Measured grouping ABCBD instead of ABABC; loudness alone must never mean "Chorus".
- **Live fill:** never invent a third without evidence; stop after a silent cycle.
- **Arranger:** sung sections follow the melody; interludes get the matched hook instrument.
- **UI:** relabel "Guess 21%" as section-name confidence and show tone match separately.
- **Code:** move the import pipeline from the two app orchestrators into TonePilotCore, so iOS and Android share it.

**3. What should we replace?**
- **Beat and downbeat stage:** by Beat This!, if it measures better. Measured today: no-drum beat F 0.52, meter 10/24.
- **Tone and instrument evidence:** by a small TonePilot timbre model. Measured today: lead 4/12 exact, backing 2/12.
- **Demucs weights, for any commercial release:** the Demucs README says their licence "is not clear", and 6-part is "likely" non-commercial. Personal builds are unaffected.

**4. Best three model integrations**

| # | Model | Job | Size | Licence |
|---|---|---|---|---|
| 1 | Beat This! small | Beats, downbeats, bars, meter | ~8.1 MB | MIT code and weights (SAFE) |
| 2 | Basic Pitch | Note events from the accompaniment stems (and a melody cross-check) | to measure | Apache-2.0, weights in repo (SAFE; training-data provenance recorded) |
| 3 | TonePilot Timbre model (own) | Instrument recognition + embeddings for tone matching | ≤ 5 MB target | Own; SAFE once its training data is cleared |

**5. Free and commercially safe today**
Beat This! (code and weights MIT), Basic Pitch (Apache-2.0), Apple SoundAnalysis / Core ML, demucs.cpp (MIT), Eigen (MPL-2.0), LAME (LGPL, with obligations), GeneralUser GS for playback, librosa/`mir_eval` ideas and tooling (ISC/MIT), and our own code.

**6. Reject**
- **Non-commercial:** madmom models (CC BY-NC-SA), MuQ and MuQ-MuLan (CC BY-NC), Sheet Sage (CC BY-NC-SA, plus 10 GB), Open-Unmix UMXL (CC BY-NC-SA).
- **Weights not cleared:** MERT (and 95–330M parameters, too large), MT3, Omnizart, RMVPE, ROSVOT, All-In-One, BEATs, Spleeter, RoFormer community checkpoints.
- **Duplicates Apple's classifier:** YAMNet.
- **Paid APIs:** all of them.

LAION-CLAP, Microsoft CLAP and PANNs are **UNVERIFIED**: their weight licences sit on Hugging Face and Zenodo, which this session couldn't open. They stay research comparisons until verified **and** measured better.

**7. What will improve instrument and tone recognition?**
- Two separate outputs: *recognition* (what is playing) and *matching* (which TonePilot tone).
- One small model trained on commercially cleared data, run on 3 s windows of each stem.
- Library tones embedded at several pitches and velocities at build time; nearest-tone retrieval; the existing ToneMatcher only fine-tunes EQ and reverb.
- Honest family-level claims for Indian instruments until licensed recordings exist.
- Graded only against ground truth plus your blind listening, never by the model's own score.

**8. What will improve rhythm and structure?**
- Beat This! downbeats fused with the current tempo estimate, giving one shared bar grid.
- Meter taken from downbeats, with compound 6/8 from the beat subdivision.
- Structure computed on bars, with key-invariant repeat grouping and vocal presence for section types.
- Three honest states: detected boundary, predicted type, guess.

**9. What will improve exact broken-chord extraction?**
In order of measured impact:
1. **Correct bars and meter** (Beat This!).
2. **Correct chords** (DSP upgrade).
3. **Real note events** from the accompaniment stem (Basic Pitch), feeding the existing chord-relative learner with octave, duration, accent and per-section variations.
4. **Phrase-versus-pattern detection**, so solos and hooks aren't forced into arpeggios.
5. **A/B validation** against the original separated part before live fill uses a pattern.

**10. Implementation order**
Phase 1 licence verification → 2 benchmark harness → 3 rhythm (Beat This!) → 4 chords and structure (DSP) → 5 accompaniment transcription and pattern learning (Basic Pitch) → 6 live Song Arpeggio rules → 7 instruments and tones (own timbre model; can run in parallel once training data clears) → 8 melody and separation only on measured gains → 9 full regression.

This differs from the suggested order: rhythm moves ahead of instruments, because the audit measured beats, meter and chords as the bottleneck for the highest-priority feature.

---

**Decisions needed from the owner**
1. Approve the roadmap order (rhythm before tones).
2. Allow `huggingface.co` and `zenodo.org` in the session's network settings, or approve reading them in CI, to finish licence verification.
3. Approve contacting the GeneralUser GS author about training permission.
4. Decide the commercial-release position on Demucs: personal builds only for now, seek permission, or plan our own separator.
5. Agree the benchmark gates in `TONEPILOT_BENCHMARK_PLAN.md` §6.
