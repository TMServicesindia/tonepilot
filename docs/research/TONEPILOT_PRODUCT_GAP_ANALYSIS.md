# TonePilot — Product Gap Analysis (Phase A)

**Date:** 2 November 2026. **Status:** research and recommendations only. No implementation.

Companion documents:
- [Competitor research](TONEPILOT_COMPETITOR_RESEARCH.md) (evidence and sources);
- [Product roadmap](TONEPILOT_PRODUCT_ROADMAP.md).

## 1. What competitors already solve (Level 1 / 2 / 3)

| Level | Question | Who solves it publicly | Gap for a CT-X870IN player of Tamil/Telugu/Hindi film music |
|---|---|---|---|
| **1. Analysis** | What is in the song? | **Well covered.** Moises, Chord AI, Muse Forge, BandLab and Steminize all offer stems, chords, key, BPM and (some) sections | Accuracy on dense Indian orchestration, Indian rhythmic cycles and modal or drone harmony is undocumented everywhere. No one publishes Indian-instrument recognition |
| **2. Reconstruction** | Which notes and roles make up the arrangement? | **Partly.** RipX has note-level editing per stem (desktop, paid); Muse Forge produces a piano *reduction*; BandLab and Chord AI convert stems to MIDI | No product documents instrument-role reconstruction: "the violin section plays this counter-melody; the guitar plays this arpeggio in the interlude" |
| **3. Keyboard performance** | How does a keyboard player reproduce it? | **Pieces.** Yamaha Chord Tracker sends chords to Yamaha keyboards and suppresses the melody; OtoTheory plays generic grooves behind chords | Nothing documented for Casio CT-X. Casio's own app supports only CT-S and LK-S. Nothing gives song-specific left-hand patterns, or tones matched to the original instruments |

**Conclusion:** Level 1 is commodity, so TonePilot should reuse open models and not compete on separation polish. The documented white space is Level 2 → Level 3 for one keyboard family and one music culture.

## 2. TonePilot's actual implementation (inspected 2 Nov 2026)

Classes:
- **T** = implemented and tested (automated tests pass);
- **V** = implemented but not adequately validated (no real-song or on-device evidence);
- **P** = prototype / research only (not wired into the app, or developer-only);
- **PL** = planned;
- **M** = missing.

| Feature | Class | Evidence (repository) | What is missing |
|---|---|---|---|
| Song import and playback | **T** (simulator) | One-step import (MP3/M4A/WAV/AIFF, ID3 tags) in `AppModel`; `SectionPlayer`; the stress test drives every Song Studio page (`App/UITests`) | Owner-device regression only |
| Song workspace (Song Studio: Mix / My keys / Arpeggio / Sections) | **T** (simulator) | `SongStudioView.swift` pages, timeline, transport, stem tiles; identifiers in the stress test | Instrument lanes and chord lane as first-class timeline rows |
| Audio separation | **T** (CI quality gate) / **V** (real songs) | Demucs 4- and 6-part Core ML downloaded in-app (`models-v1`), C++ fallback (`StemSeparator`); `coreml-convert.yml` compares against PyTorch per part | **Licence:** Demucs weights not cleared for commercial use, so personal builds only. No real Indian-song quality measure |
| Lead/backing split of "other" | **T** | `LeadSplitter` + tests; speed budget 3.9 s per 4 min | Real-song validation |
| Instrument recognition (production) | **V** | Apple SoundAnalysis (`InstrumentRecognizer.swift`); 14/19 clean synthetic instruments (CI) | The owner's real-song test was poor. No Indian-instrument labels |
| Instrument recognition (EfficientAT + head C) | **P** | Gate 1 v2–v4b synthetic proxy; Gate 2 Core ML Mac measured; developer-only shadow mode (`DeveloperShadowMode.swift`, off by default) | Real licensed recordings; physical iPhone (G2.4); the ≤5% wrong-family target is not met on all conditions |
| Tone matching (ToneMatcher / PartMatcher) | **V** | Core tests (8 files); audit: lead 4/12 exact, backing 2/12 | The owner's real-song test was poor ("Cinematic Low Strings" everywhere). The confidence label was confusing |
| Instrument Maker / Tone Studio | **T** (engine) | 8-layer tones, SF2 parser, user multisamples, ADSR, filter, EQ, sends, mono/legato; 26-tone Film Tone Library | No tones yet for tabla, mridangam, dholak, ghatam, kanjira, thavil, dhol, electronic percussion, frame drums or ambient textures. No "match this stem" A/B loop on real songs |
| Song analysis: tempo / beat / key / chords / sections | **T** (synthetic) / **V** (real) | Audit (synthetic): beats F 0.92 with drums, 0.52 without; chords 70% of bars, minor keys 25–44%; time signature 10/24; section grouping wrong | Real annotated Tamil/Telugu/Hindi songs (Gate 3). Indian cycles (Phase 2 `RhythmCycle` is core-only) |
| Harmony hypotheses / rhythm cycle / Beat This! | **P** | Core-only (`Harmony/`, `Rhythm/`); Phase 2–3 reports | Not wired into the app; Beat This! not adopted (no gain shown) |
| Melody Player (right hand) | **T** | Melody/Chord guide (`MelodyChordGuideView`), Free Play, NoteRouter, ToneEngine. Protected; no regressions allowed | Octave/register guidance on real songs |
| Chord Player (left hand) | **V** / partial | Chord guide and voicings (`SectionGuideView`); chord memory in live fill | No dedicated Chord Player mode with root–5th–root input coaching |
| Accompaniment Maker | **T** (AutoArranger) / **P** (classifier) | `AutoArranger` (versions, switching); `AccompanimentClassifier` (no-fill-unless-sure) core-only, 4 safety tests; Phase 4: 0/7 false arpeggios | Wiring the classifier; pattern fidelity with *estimated* inputs (TODO 6.3) |
| Live Song Arpeggio | **T** (core) / **V** (device) | `LiveFill` (v0.3.71 deadlock fix, tests); `ArpeggioLearner` 100% degrees with true beats and chords | Accuracy with estimated beats and chords on real songs; latency on the owner's Casio |
| MIDI input | **T** (core) / **V** (device) | `MIDIInputManager` (CoreMIDI), MIDI parser tests (16) | CT-X870IN specifics (Local Control, which controllers it sends): hardware checklist |
| MIDI output (to the Casio or export) | **M** | No MIDI output path found in the sources | Decide whether it is needed: TonePilot plays its own engine into the Casio AUDIO IN |
| Casio integration | **V** | USB-MIDI in + audio to AUDIO IN (documented path); `docs/HARDWARE_TEST_CHECKLIST.md` | Hardware test results on the owner's CT-X870IN |
| Core ML inference | **T** (Demucs in production) / **P** (EfficientAT) | `CoreMLBackend` + contract test (max error 9.5e-7; 28.3 ms test model, Mac CI) | Physical-iPhone numbers for EfficientAT (pending) |
| Recording / MP3 export | **T** | Record tab, LAME encoder; stress test `testRecordAndSaveMP3` | — |

**Contradictions flagged, not resolved:**
- `docs/CAPABILITIES.md` (118 tests) is stale; the current build runs 224 core tests.
- The owner's earliest framing ("instrument recognition and tone matching are secondary to accompaniment reconstruction", PROJECT_MEMORY §1) differs from the later "Instrument Analyser = main differentiation". This document treats accompaniment as the core value and the instrument analyser as its enabler (see §4), pending the owner's confirmation.

## 3. Is the positioning genuinely differentiated?

**Differentiated (documented white space):**
1. **Song-specific left-hand patterns for the player's own chords.**
   - Live Song Arpeggio follows the player's root–5th–root on the Casio and plays the *song's* learned pattern, in time with the song.
   - Publicly, no product documents this. OtoTheory and Yamaha use generic grooves or styles.
2. **Tones chosen for the original song's instruments, playable live from the Casio,** including Indian film instruments such as nadaswaram, shehnai, veena, santoor, sarangi and kuzhal.
3. **Casio CT-X support.** Casio's own app excludes the CT-X series (Casio notice).
4. **Indian film-music awareness:** rhythmic cycles, drone and modal harmony, composer-era tone libraries, and honest "unknown" answers.

**Not differentiated (do not claim):**
- Phone-to-keyboard companionship (Yamaha Chord Tracker);
- stem separation;
- chord, key or BPM display;
- piano transcription;
- generic backing grooves.

**Biggest risks:**
1. **Real-song accuracy is unproven.** Every analysis number is synthetic or proxy, and the owner's real-song tone test was poor. Without Gate 3 (licensed real recordings, annotations), differentiation is a claim, not a product.
2. **Separation licence.** Demucs weights are not cleared commercially, so a public release needs another model or permission. The permission emails are drafts awaiting the owner.
3. **Input quality limits the pattern quality.** `ArpeggioLearner` is 100% with true beats and chords, but beats without drums are only F 0.52 and minor-key chords 25–44%. The bottleneck is upstream analysis.
4. **Scope creep toward a DAW** (note editing, sound replacement). RipX and BandLab already do these.
5. **Casio hardware unknowns:** Local Control, controllers sent over USB, and audio-in latency.

## 4. Proposed positioning

> **TonePilot turns a song you're allowed to play into a keyboard performance on your Casio: the right tones for its instruments, the melody for your right hand, and the song's own accompaniment pattern following your left hand, in time with the original backing.**

Product shape: **Song → Arrangement understanding → Playable keyboard performance.** This is not a DAW, not a separator, and not a sheet-music app.

## 5. Accompaniment approaches compared (the core decision)

| Approach | What it is | Who does it | Fit for TonePilot | Risk |
|---|---|---|---|---|
| A. Generic backing from chords | Pads or strums over detected chords | Many apps | **Low:** not song-specific | Sounds unlike the film song |
| B. Predefined grooves | Library of drum, bass and chord grooves | OtoTheory, keyboard styles (Yamaha) | **Low–medium:** a fallback only | Commodity; the Casio already has styles |
| C. Arpeggios from detected chords and tempo | Rule-based patterns | Arpeggiator apps | **Medium:** a safe default when learning fails | Generic; can invent wrong notes |
| D. Full reconstruction of each instrument's original pattern | Note-level, every instrument | RipX partly (desktop, manual) | **High value, high risk:** long-term only | Needs accurate transcription of dense mixes |
| **E. Hybrid** | Keep the **real separated backing** (drums, bass, other) as the reference bed; generate only the part the player performs (left-hand song pattern via Live Song Arpeggio; right-hand melody guide) | **Nobody documented** | **Recommended** | Depends on separation quality (licence) and beat/chord accuracy |

**Recommendation: E, with D applied narrowly.**
- Learn only the one accompaniment figure per section that the left hand replaces. This is what `ArpeggioLearner` already does.
- Keep the no-fill-unless-sure rule. When uncertain, the separated backing plays and nothing is generated.
- Never add thirds the song doesn't have.
- The player's root–5th–root on the Casio selects the chord. TonePilot plays the song's pattern for that chord, aligned to the song's beat, and stops on silence, a full chord, or a section end.

## 6. Recommended experience (navigation and journey)

**Navigation:**
- Library;
- **Song workspace** (the centre of the app);
- Tones;
- Record;
- Settings.

Inside a song, the workspace offers performance modes rather than separate apps:

1. **Workspace** (today's Song Studio Mix + Sections):
   - Timeline lanes: sections · chords · beats · **instrument lanes** (family / instrument / unknown, with confidence and entry and exit times) · stems with volume.
   - Analysis progress per stage.
   - Correction tools: chord, section boundary, instrument label (corrections are saved as ground truth candidates, never as model truth).
2. **Tones** (Instrument Maker):
   - per instrument lane, "matching tones" with A/B against the stem;
   - layering;
   - ADSR, EQ and reverb (all exist in Tone Studio);
   - save as a playable tone.
3. **Melody** (right hand):
   - section-aware melody guide, octave/register hint, matching tone, loop and speed.
4. **Chords and Arpeggio** (left hand):
   - root–5th–root coaching;
   - detected chord from the Casio;
   - the song's learned pattern;
   - assist / manual / auto modes;
   - independent backing, bass and drum levels;
   - original separated backing as reference.
5. **Live** (performance):
   - Casio over USB MIDI;
   - Live Song Arpeggio synced to the song's beat;
   - explicit uncertainty behaviour (no fill, with an indicator);
   - low-latency path.

**First-session journey:**
1. Import a song.
2. Watch the staged progress: decode → separate → beats/chords/sections → instruments → patterns.
3. See the workspace with sections and instrument lanes.
4. Press "Play this song on my Casio".
5. TonePilot proposes a tone per section plus melody and left-hand modes.
6. Play.
7. Save the project (already automatic).

## 7. Recommended product architecture (unchanged principles)

- **Analysis chain (approved, revision 3):**
  1. rhythm (beat evidence → cycle inference);
  2. harmony hypotheses;
  3. note events per stem;
  4. accompaniment type (default no fill);
  5. pattern learning;
  6. live fill.
- **Instrument Analyser** feeds the tone suggestions and the instrument lanes only. It never changes patterns or saved arrangements until it is validated on real audio (shadow mode first).
- **Reuse, don't rebuild:**
  - separation: Demucs today; a licence-clean replacement is to be found;
  - Basic Pitch (Apache-2.0) for note events on stems where it measures better;
  - BTC chords (MIT) and All-In-One (MIT) as candidates to *benchmark*, not adopt by default.

## 8. Real-world evaluation strategy (summary; details in the roadmap §4)

- **Legal audio:**
  - owner recordings and Casio performances;
  - licensed Indian instrument recordings (Commons candidates after verification);
  - permitted film recordings only after a legal check.
  - Never ripped MP3s or YouTube downloads.
- **Splits:** by song identity. TRAIN / DEV / TEST never share a song; the 20-song catalogue stays independent of training and threshold tuning.
- **Ground truth:** human-verified annotations (instrument, role, entry/exit, chords, beats, sections, accompaniment figure). AI pre-fill is allowed, but predictions are never ground truth.
- **Reporting:**
  - per language (Tamil / Telugu / Hindi) and per family;
  - coverage, wrong-family rate, selective accuracy and unknown rate together;
  - full-song processing time on a **physical iPhone**, labelled separately from Mac CI.
