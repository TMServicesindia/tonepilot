# TonePilot AI — capability matrix

Status key:
* ✅ **Implemented & tested**: covered by automated tests that pass. Core logic was run on Linux; on-device behaviour still needs the hardware checklist.
* 🟡 **Implemented, not yet verified on device**: iOS code written against the iOS 17 SDK but not compiled here (no Xcode on Linux; every file passes a Swift syntax parse).
* 🔶 **Partial**
* ⏳ **Planned**
* ⛔ **Blocked** (licensing, hardware or technical)

Totals: **82 Swift tests** (80 run by default; 2 need environment variables — the live server round trip and the demo render — and both passed when run) and **8 Python tests**, all passing. They include tests against the real GeneralUser GS SoundFont (287 presets) and real Spotify Basic Pitch 0.4.0.

## 1. Live playing on the Casio CT-X870IN (priority 1)

| Capability | Status | Evidence / notes |
|---|---|---|
| USB-MIDI input: note on/off, velocity, running status, active-sensing filtering, UMP (MIDI 1.0) | ✅ core · 🟡 CoreMIDI | `MIDITests` (16 tests) |
| Sustain pedal, pitch bend (per-layer bend range), mod wheel → vibrato, expression CC | ✅ | `EngineTests.testSustainPedalHoldsThenReleases`, `testPitchBend` |
| Stuck-note prevention: note-off releases exactly what started, through transpose/arrangement changes, retriggers and channel duplicates | ✅ | `NoteRouterTests`, `testControllerKeepsHeldNotesAcrossArrangementSwitch` |
| All-notes-off / panic; auto-panic on cable unplug and audio interruption | ✅ core · 🟡 app | |
| Hot-plug reconnection without restarting | 🟡 | `MIDIInputManager.refreshSources` on CoreMIDI notifications |
| Audio into the Casio AUDIO IN | 🟡 | Documented path (3.5 mm from a USB-C hub or USB audio interface). The app warns when output is the iPhone speaker. **Hardware test required.** |
| CT-X870IN specifics: Local Control, which controllers it sends over USB | ⛔ until tested | Not confirmed from Casio documentation; the checklist records them |

## 2. Sample-based instrument engine (priority 2)

| Capability | Status | Evidence / notes |
|---|---|---|
| SoundFont (SF2) parser: presets, instrument/preset generator merging, key/velocity zones, loops, root/tuning, envelopes, filter, attenuation, pan | ✅ | Synthetic SF2 tests and the real GeneralUser GS: all 43 GM factory patches and 12 extended patches (including the drum kit on bank 128) load |
| Pitch accuracy (Hermite interpolation, keyboard tracking) | ✅ | Measured 441/882/220.5 Hz from a 441 Hz sample; real piano A4 at 440 ± 6 Hz |
| Loop modes, release, voice stealing, 96-voice polyphony | ✅ | |
| User multisample instruments (WAV/MP3/M4A via AVFoundation): trim, root note, key/velocity ranges, loop points, ADSR | ✅ core · 🟡 UI | `testWAVRoundTripAndUserSampleInstrument`. The app warns when one sample is stretched more than 7 semitones |
| Synthesized patches (saw/square/triangle/sine, detune, sub, breath noise) | ✅ | Vocal-like Lead, Soft Synth Lead, Warm Analog Pad, Plucked Synth |
| Real-time safety: no allocation, locks or I/O in render; non-blocking command queue (`trylock`) | ✅ by design | 18× real time with 60 voices plus all effects (x86 container). **iPhone profiling pending** |
| Legacy Apple `AVAudioUnitSampler` engine as a fallback | 🟡 | Selectable in Settings |

## 3. Composite tones & controls (priority 3)

| Capability | Status | Notes |
|---|---|---|
| Up to 8 live layers: stack, split, velocity-switched | ✅ | |
| Per layer: volume, pan, octave, transpose, fine tune, key range, velocity range, mute/solo/enable, MIDI channel | ✅ | |
| Per layer: ADSR override, low-pass filter (cutoff/resonance), 3-band EQ, reverb/chorus/delay sends | ✅ | Real DSP, measured in tests (filter, attack) |
| Per layer: mono/legato, glide, vibrato (depth/rate/delay), bend range, velocity response | ✅ | `testMonoLegatoGlidesAndReturnsToHeldNote` |
| Master: gain, 3-band EQ, reverb (Freeverb), chorus, stereo delay, output meter, brick-wall limiter | ✅ | `testLimiterPreventsClipping` (8 layers × 9 notes ≤ 0.95) |
| Gain headroom for stacked layers | ✅ | |

## 4. Presets & section arrangements (priority 4)

| Capability | Status | Notes |
|---|---|---|
| Versioned library (schema v3), migrations v1→v2→v3, atomic save with backup recovery | ✅ | |
| Song library: search, favourites, playlists, multiple tones per song, tone per section | ✅ core · 🟡 UI | |
| **AI Original** (kept unchanged) + **My Version** (editable); restore AI Original; edit-just-this-section | ✅ | `testRestoreAIOriginalAndDetach` |
| **Regenerate This Section** without reprocessing the song | ✅ | `testRegenerateOneSection…` |
| Preset export/import (`.tonepilot.json`, lists required sample files); duplicate/rename | ✅ | |
| Backup of library, samples and stems | 🟡 | `LibraryStore.exportBackup` + share sheet |

## 5. Import & real audio analysis (priority 5)

| Capability | Status | Notes |
|---|---|---|
| MP3/M4A/WAV/AIFF import with a rights confirmation; YouTube = link only | ✅ core · 🟡 UI | No YouTube downloading, by policy |
| Tempo + beat grid (DP beat tracking), ×2/÷2 fix | ✅ | ±2.5 BPM, beats within 40 ms on test material |
| Key (with harmonic subtraction), per-section key change | ✅ | C major and A minor tests |
| Chords (maj/min) with alternatives; Viterbi smoothing | ✅ | Extended or modal harmony is simplified, so a drone guide is offered instead |
| Time signature (3 vs 4) | ✅ | Accent-periodicity estimate |
| Structure: boundaries, repetition groups, section types using lead-line presence | ✅ | Instrumental vs sung sections inferred from the melody, not a vocal detector (unless stems are used) |
| One-click pipeline: analyse → arrange → save | ✅ | `testOneClickPipelineProducesPlayableSongAwareArrangement` |

## 6. Section detection & instrument recommendations (priority 6)

| Capability | Status | Notes |
|---|---|---|
| Per-section activity: lead/vocal melody, pad/strings, keys, accents, bass, percussion, each with written evidence | ✅ | From mix features, or stem levels when the server is used |
| Lead-sound matching (register, ornamentation, brightness, sustain, vocal source) over 10 lead candidates | ✅ | Bansuri-like flute, violin, vocal-like lead, shehnai, santoor-like, veena-like, piano, celesta… |
| Automatic per-section arrangement: RH lead, LH accompaniment for Root–Fifth–Root, support layers only when heard, split point, effects | ✅ | Rationale stored with each tone |
| Trained instrument-classification model (e.g. a PANNs/YAMNet-style tagger) | ⏳ | Not integrated. Recommendations are evidence-based rules, labelled as such in the UI |
| Exact studio-instrument reproduction | ⛔ | Not achievable from a mix. The app says "closest available sounds — approximations" |

## 7. Vocal removal & playable melody (priority 7)

| Capability | Status | Notes |
|---|---|---|
| On-device predominant-melody extraction with slides/vibrato/gamaka kept as pitch curves | ✅ | Note-exact on test tunes over accompaniment; vibrato and slides stay inside one ornamented note |
| Plausibility check (chord roots ≠ melody) | ✅ | |
| Difficult-phrase flags | ✅ | |
| Vocal stem separation (Demucs) on your Mac/server | 🔶 | Server code and tests written; **Demucs itself not run here** (its weights couldn't be downloaded in this environment) |
| Vocal-stem transcription with Basic Pitch + overtone cleanup | ✅ | Real Basic Pitch run; Swift ↔ Python live round trip passes |
| Live Play Mode (play the melody with the section's lead tone; guide shows the keys, octave-compensated) | ✅ core · 🟡 UI | |
| Reference Learning Mode (app plays the melody through the guide voice) | ✅ core · 🟡 UI | Sample-accurate sequencer |
| Note correction, octave shift, transposition, guide patch change | ✅ core · 🟡 UI | |
| Pitch-bend playback of ornaments in the guide voice | ⏳ | The guide plays note pitches; bends are shown, not yet sent |

## 8. Chord guidance for Root → Fifth → Root (priority 8)

| Capability | Status | Notes |
|---|---|---|
| Chord name, timing, root/fifth/octave notes within the left-hand range (C2–B3) | ✅ | C→G→C, G→D→G, A→E→A, F→C→F verified |
| Alternatives, confidence, user correction, transposition | ✅ | |
| Tonic drone (Sa–Pa) when no clear chord exists | ✅ | Avoids forcing Western chords onto modal passages |
| Generated bass (root → fifth), drums (4 styles), metronome, each independently on/off with its own level; all off by default | ✅ core · 🟡 UI | `testAccompanimentEvents`, `testAccompanimentPlaysThroughEngine` |

## 9. Automatic tone switching (priority 9)

| Capability | Status | Notes |
|---|---|---|
| Automatic / Manual / Assisted modes, lead time, seeking | ✅ | `PerformanceLogicTests` |
| Timing reference: backing-track position, a tap-started timer, or none (no claims from MIDI alone) | ✅ core · 🟡 UI | |
| Preloading upcoming section instruments; held notes preserved across switches | ✅ | |

## 10. Performance & reliability (priority 10)

| Capability | Status | Notes |
|---|---|---|
| Latency, CPU and layer-count limits on a real iPhone | ⏳ | Needs the device; see the checklist |
| Interruption / route-change recovery | 🟡 | |
| UI responsiveness during analysis (background tasks, progress, cancel, resume) | 🟡 | |
