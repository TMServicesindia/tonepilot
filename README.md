# TonePilot — AI-assisted instrument tone studio for the Casio CT-X870IN

Play layered film-song tones (piano + strings + bell, pads, flutes…) from your **Casio's own keys**, generated on your **iPhone** and heard through the **Casio's speakers**. Import an MP3 you own, let TonePilot analyse it on-device, then build a different tone for each intro, interlude and chorus.

> YouTube links are stored as references only. YouTube's terms forbid downloading or separating its audio, so the MVP analyses **imported audio files** (MP3/M4A/WAV/AIFF).

The research, architecture, licensing and hardware plan are in **[docs/FEASIBILITY.md](docs/FEASIBILITY.md)**.

## What works today vs. what doesn't

| Area | Status |
|---|---|
| Casio → iPhone USB MIDI (note on/off, velocity, sustain, pitch bend, hot-plug, stuck-note protection) | Implemented. Routing logic unit-tested; CoreMIDI code needs on-device testing |
| Layered / split / velocity-switched tones, up to 6 layers, per-layer volume, pan, octave, transpose, fine-tune, key range, velocity range, MIDI channel, mute/solo, reverb, delay | Implemented. Router logic unit-tested |
| Sound source: General MIDI presets from an SF2 SoundFont via `AVAudioUnitSampler` | Implemented. **You install the SoundFont** (see below) |
| Peak limiter, gain headroom for stacks, output meter + clip light, panic | Implemented |
| Song library, search, favourites, playlists, multiple tones per song, tone per section | Implemented |
| MP3 import + on-device analysis: tempo & beats, key, chords (maj/min), section boundaries, repeated-section groups, section-type guesses | Implemented and **tested on synthetic audio**. Confidence shown; BPM/key/sections editable |
| Section editor (rename, retype, resize, split, merge, delete, snap to beats) and section loop playback | Implemented |
| Tone suggestions per section | **Heuristic** (brightness, attack, sustain rules), labelled as such. Not instrument recognition |
| Performance mode (big section buttons, layer mutes, master, playlists, panic) | Implemented |
| Per-layer attack/release, filter UI, user samples / multisample builder | **Not yet** (Milestone 3). SF2 envelopes are used as-is |
| Stem separation (Demucs), note transcription (Basic Pitch), instrument recognition | **Not yet** (Milestones 4–5, Mac/server) |

## Run it

Requirements: a Mac with **Xcode 15+**, an iPhone on **iOS 17+**, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cd TonePilot
xcodegen generate          # creates TonePilot.xcodeproj from project.yml
open TonePilot.xcodeproj
```

1. In **Signing & Capabilities**, choose your team and change the bundle id if needed.
2. Get the sounds: download **GeneralUser GS** (free) from <https://github.com/mrbumpy409/GeneralUser-GS> and rename the `.sf2` to `GeneralUser-GS.sf2`. Then do one of these:
   * put it in `App/Resources/SoundFonts/` before building (it's bundled and installed on first launch), or
   * AirDrop it to the phone and import it in **Settings › SoundFonts**.
3. Run on your iPhone. The Simulator works for the UI and analysis, but has no USB MIDI.
4. Connect the Casio. Follow the in-app **Settings › Connect your Casio CT-X870IN** and [docs/HARDWARE_TEST_CHECKLIST.md](docs/HARDWARE_TEST_CHECKLIST.md).

### Tests

The core logic (models, persistence and migrations, MIDI parsing and routing, analysis) is a Swift package with 38 unit tests:

```bash
cd Packages/TonePilotCore && swift test            # macOS or Linux
# no Swift installed? docker run --rm -v "$PWD":/pkg -w /pkg swift:6.0-noble swift test
```

The analysis tests synthesize songs with known tempo, key, chords and an A-B-A-B structure, and check that the analyser recovers them.

## Project layout

```
project.yml                         XcodeGen spec (iOS 17 app + local package)
App/Sources/
  TonePilotApp.swift                App entry, tabs, first-run setup sheet
  Services/AppModel.swift           Library state, MIDI→router→engine wiring, import, analysis jobs, audio-session handling
  Audio/SoundEngine.swift           AVAudioEngine: 6 sampler slots (EQ→delay→reverb→mixer), limiter, meter
  Audio/AudioFileDecoder.swift      MP3/M4A/WAV → mono 22.05 kHz floats for analysis
  Audio/SectionPlayer.swift         Play/loop a song section through the same output
  MIDI/MIDIInputManager.swift       CoreMIDI (UMP, MIDI 1.0), hot-plug, activity log
  Views/                            Library, Import, Song detail & timeline, Tone Studio, Performance, Settings/Diagnostics
App/Resources/SoundFonts/           Drop GeneralUser-GS.sf2 here (not committed)
Packages/TonePilotCore/
  Models/                           Song, Section, Arrangement, Layer, InstrumentPatch, Library, factory GM patches, section editing
  Persistence/LibraryStore.swift    Versioned JSON, v1→v2 migration, atomic save + backup recovery
  MIDI/                             Byte/UMP parser, NoteRouter (layers, splits, ref-counted voices, panic), velocity curves, gain staging
  Analysis/                         FFT, features, tempo + DP beat tracking, key/chords, structure segmentation, SongAnalyzer
  Suggestions/ToneSuggester.swift   Transparent rule-based tone suggestions
docs/                               Feasibility report, hardware checklist
```

## Honest limitations

* The iOS target was written against the iOS 17 SDK but **has not been compiled in this environment** (no Xcode on Linux). The `TonePilotCore` package is compiled and tested. Expect to fix minor compile issues in the app target on first build.
* Analysis is classical DSP. It works well on clear rhythms and harmony, but is less reliable on dense film mixes, drones, modal melodies and tempo changes. Every value shows a confidence badge and can be corrected.
* Section labels (intro, verse, chorus) are guesses from repetition and loudness. Vocals aren't detected yet.
* The connection guide is based on general iOS/USB-MIDI behaviour and retailer specs. CT-X870IN-specific behaviour (Local Control, which controllers are sent over USB) is still unverified; use the checklist.
