# TonePilot — Recommended Architecture

**Date:** 1 November 2026 · **Status:** proposal for the owner's approval; nothing implemented.

**The recommendation in one line:** keep the working engine and pipeline, fix the inputs Song Arpeggio depends on (beats, downbeats, meter, chords) with **one small MIT model (Beat This!) plus DSP upgrades**, get real note events from the accompaniment with **one Apache-2.0 model (Basic Pitch)**, and replace self-graded tone matching with **one small TonePilot-trained timbre model** — three models at most, each gated by a measured win over today's code.

Evidence labels (Measured / Source / Estimate / Unknown) follow `TONEPILOT_ARCHITECTURE_AUDIT.md`.

---

## 1. Design principles

1. **Accuracy before model count.** A model is added only when the benchmark shows it beats the current TonePilot code on independent data.
2. **Shared core first.** All analysis logic lives in TonePilotCore so iOS and Android get it once; platform code only runs inference (Core ML on iOS, ONNX Runtime or TFLite on Android).
3. **Separate the questions.** *What is playing?* (recognition), *which TonePilot tone fits?* (matching), *where are the beats and bars?* (rhythm), *what notes does the accompaniment play?* (transcription), *what is the repeatable pattern?* (pattern learning) are separate stages with separate tests.
4. **Confidence is part of every answer.** Each stage returns a value, a confidence and an explanation; low confidence produces a "guess" state the UI shows honestly, never a confident label.
5. **Live playing is untouchable.** No analysis runs on the main thread or the MIDI/audio threads; live fill keeps working with the song paused.

## 2. End-to-end data flow

```
Import (audio the user has rights to)
 │
 ├─ 1. Decode + first analysis (existing, DSP)              mono 22.05 kHz
 │
 ├─ 2. Separation (existing Demucs; licence gate for commercial builds)
 │      vocals · drums · bass · other (+ piano · guitar) → other → Lead / Backing (existing DSP)
 │
 ├─ 3. RHYTHM  (new: Beat This! small, MIT, ~8.1 MB)
 │      mix → beat + downbeat activations
 │      fused with TempoAnalyzer onset tempo (existing) → beat grid, bars, meter, tempo curve
 │      confidence = agreement between the two + activation peakiness
 │
 ├─ 4. HARMONY (improved DSP, no model)
 │      bass stem → root evidence · other/backing → bass-free chroma
 │      key-aware chord HMM (major + minor keys, 7ths folded to triads) on bar/beat grid
 │      → chords with confidence + alternatives
 │
 ├─ 5. STRUCTURE (improved DSP, no model)
 │      bar-aligned features → novelty boundaries (existing) + key-invariant repeat grouping
 │      vocal presence (vocals stem) + repetition + energy → section type with tiers:
 │      boundary (detected) · type (predicted, with confidence) · guess (shown as guess)
 │
 ├─ 6. TRANSCRIPTION (new: Basic Pitch, Apache-2.0)
 │      piano / guitar / backing stems (whichever carry the accompaniment) → note events
 │      (onset, offset, pitch, velocity, bends)
 │
 ├─ 7. PATTERN LEARNING (existing ArpeggioLearner, extended)
 │      note events + bars + chords → chord-relative events per section
 │      (beat position, degree, octave, duration, accent, register, variation, confidence)
 │      fallback: current onset + harmonic probe when transcription confidence is low
 │
 ├─ 8. RECOGNITION (new: TonePilot Timbre model, own, ≤5 MB target; Apple classifier as prior on iOS)
 │      each instrument stem, 3 s windows, 50% overlap → family/instrument probabilities
 │      + role from stem and register (lead / backing / bass) + articulation from DSP
 │      → instrument timeline per section, with confidence
 │
 ├─ 9. TONE MATCHING (new retrieval + existing fine-tune)
 │      Timbre-model embedding of each stem vs pre-computed embeddings of every library tone
 │      rendered at several pitches and velocities → top-3 tones per part per section
 │      → existing ToneMatcher fits EQ + reverb on the winner only
 │
 └─ 10. ARRANGER (existing, policy fixed)
        sung sections → melody-suited lead · instrumental sections → matched hook instrument
        left hand → matched backing · Main tone from the chorus · user edits never overwritten
```

## 3. Each stage in detail

### 3.1 Rhythm (highest leverage for Song Arpeggio)
- **Model:** Beat This! `small` (MIT code and weights, ~8.1 MB, [source](https://github.com/CPJKU/beat_this)); `final` (~78 MB) only if small loses measurably.
- **Why:** measured no-drum beat F 0.52 and meter 10/24 today; the arpeggio learner is 100% accurate with correct beats/bars.
- **Fusion:** Beat This! downbeats define bars and meter; TempoAnalyzer's onset autocorrelation checks tempo (half/double); disagreement lowers confidence and opens the existing ×2/÷2 correction.
- **Meter:** bars per downbeat pair → 2, 3 or 4 beats; compound 6/8 when the beat subdivides in three (from onsets and transcribed notes) — the existing `stepsPerBeat` decision moves here so pattern learning and live fill share one grid.
- **Paused practice:** the learned pattern carries its own grid; live fill uses an internal clock at the song tempo × user tempo scale (already implemented).

### 3.2 Harmony (DSP)
- Bass stem gives the root; the backing stem gives the third/fifth without the vocal.
- Key estimation adds minor-key handling (measured: minor-key songs 25–44% of bars, keys wrong) using a key-dependent chord transition prior in the existing Viterbi.
- Sevenths and inversions fold to their triad (measured 75% today).
- Output keeps the existing `confidence` and `alternatives`, which feed the live-fill third rule (§3.7).

### 3.3 Structure (DSP)
- Bar-aligned features from §3.1 instead of free beats.
- Repeat grouping with key-invariant chroma (rotate to best match) and path search, fixing the measured ABCBD grouping.
- Section type from **vocal presence** (vocals stem level), repetition count and position; loudness alone never makes a "Chorus".
- Three display states: detected boundary · predicted type with confidence · guess. The existing section editor stays the correction path.

### 3.4 Transcription
- **Model:** Basic Pitch (Apache-2.0; README lists Core ML, TFLite and ONNX conversions, [source](https://github.com/spotify/basic-pitch)).
- Runs only on the stem(s) that carry the accompaniment (piano, guitar, backing), so it works on near-monophonic or few-voice material where it "works best on one instrument at a time".
- The same model is the melody cross-check on the vocals stem (no extra model).

### 3.5 Pattern learning (existing, extended)
Each learned event stores: position (beats from the bar start), chord degree, octave offset, duration (beats), accent, register (MIDI centre), plus per-section variations and a confidence. Mapping to a new chord stays degree-based (current `ArpeggioPattern`).
- **Repetition vs phrase:** if bars do not repeat within a section (low cross-bar consistency), the section is a *phrase* (instrumental hook) — live fill offers the hook or nothing, never forces an arpeggio.
- **Validation:** A/B preview of the original separated part vs the learned pattern, note list, tap-to-correct (exists), approve per section.

### 3.6 Recognition and tone matching (two outputs, never merged)
- **Recognition** answers *what is in the recording*: per stem, 3 s windows → probabilities over instrument families and the instruments the training data supports; Indian instruments at family level unless licensed recordings exist.
- **Matching** answers *which TonePilot tone to play*: nearest neighbour between stem embeddings and library embeddings, then EQ/reverb fit (existing ToneMatcher) on the winner only.
- **Library embeddings** are computed at build time from each tone rendered at 3 registers × 2 velocities, so pitch- and velocity-dependent timbre is covered.
- **Model:** one small CNN (EfficientAT-class architecture, MIT code) trained by TonePilot on cleared data only (own synth renders; GeneralUser renders after the author's permission; Slakh2100 / NSynth after their licences are verified). LAION-CLAP stays a benchmark comparison until its weights are cleared.

### 3.7 Live fill (existing, rules tightened)
- Split point stays the default input separator (adjustable, exists); automatic hand detection only if it measures as reliable.
- Third rule: play a third only when the player played it, chord memory holds it, or the song's chord at this moment has confidence ≥ threshold; otherwise root-fifth-octave voicings.
- Stop cleanly: if no chord-hand note arrives for one pattern cycle, the fill ends.
- Never duplicate the player's notes; separate fill tone and volume; MIDI-thread processing with separate locks (exists).

## 4. Threads and performance

| Work | Thread | Budget (to enforce in CI) |
|---|---|---|
| MIDI → router → engine | CoreMIDI thread → audio thread | unchanged |
| Live fill decisions | MIDI thread | < 1 ms per note (to add as a budget) |
| Separation | background, `.userInitiated` | 2–3 min per 4-min song (owner target) |
| Beat This!, Basic Pitch, Timbre model | background queue, windowed | **≤ 60 s added per 4-min song on iPhone 15 (target, untested)** |
| UI | main thread | launch < 4 s, memory < 1.5 GB (existing gates) |

## 5. Android path

Every model runs from TonePilotCore-defined inputs/outputs; iOS uses Core ML, Android uses ONNX Runtime or TFLite with the same pre/post-processing in Swift (shared through the C bridge). Basic Pitch already publishes TFLite and ONNX; Beat This! and the Timbre model need an ONNX export (to test). Moving the import pipeline from `AppModel`/`AppCore` into TonePilotCore is part of this work.

## 6. What changes, what stays

| Stays | Changes |
|---|---|
| ToneEngine, MIDI, NoteRouter, Record, Song Studio, model download, LeadSplitter, ArpeggioLearner core, section editor, CI gates | Beat/downbeat stage (Beat This! + fusion), HarmonyAnalyzer (DSP), StructureAnalyzer (DSP), accompaniment notes (Basic Pitch), recognition and matching (Timbre model + retrieval), arranger policy, live-fill third and stop rules, pipeline moved into the core |
