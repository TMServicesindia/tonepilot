# TonePilot AI — Indian film-music keyboard studio for the Casio CT-X870IN

**Import a song → TonePilot analyses it → it builds the closest playable arrangement → connect your Casio and play.**

Left hand: Root → Fifth → Root. Right hand: the melody. TonePilot does the setup: song sections, a layered tone for each section, effects, a chord guide for your left hand, a melody guide for your right hand, and optional backing.

Sound is generated on the iPhone (TonePilot's own sample/synth engine using SoundFont instruments) and heard through the Casio's speakers via its AUDIO IN. The Casio keys drive it over USB MIDI.

> **Two ways to bring in a song:**
> * **Listen Mode** — play it in Spotify, YouTube Music, Apple Music, JioSaavn… (services you're licensed to listen to). TonePilot listens through the microphone, builds the arrangement, and discards the audio (never saved or uploaded).
> * **Import an audio file you own** (MP3/M4A/WAV/AIFF), e.g. a purchased track.
>
> TonePilot does not download from YouTube or unlicensed sites, and won't analyse files from them.

* What works and how it was verified: **[docs/CAPABILITIES.md](docs/CAPABILITIES.md)**
* Research, architecture, licences and hardware plan: **[docs/FEASIBILITY.md](docs/FEASIBILITY.md)**
* Testing with the real keyboard: **[docs/HARDWARE_TEST_CHECKLIST.md](docs/HARDWARE_TEST_CHECKLIST.md)**
* Optional vocal separation server: **[server/README.md](server/README.md)**

## The one-click flow

1. **Library › + › Listen to a song**: start the song in your streaming app; TonePilot listens until it ends. Or **Import an audio file** you own (optionally sent to *your* analysis server for vocal separation).
2. TonePilot runs, on the phone:
   * tempo and beats, key (and key changes), time signature
   * chords, with alternatives and a Sa–Pa drone where no clear chord exists
   * the lead/vocal melody with slides and vibrato preserved
   * sections and repeated parts
   * what plays in each section (lead, pad/strings, keys, bells/plucks, bass, percussion)
3. **AutoArranger** builds every section's tone:
   * a right-hand lead matched to the melody (e.g. a Bansuri-like flute for ornamented, sustained lines)
   * a left-hand accompaniment sound suited to Root–Fifth–Root
   * support layers only where they were heard, plus key split and effects
   * a written explanation of why
   Each tone is saved twice, as an unchanged **AI Original** and an editable **My Version**.
4. **Play on My Casio**. Tones switch by section **automatically** (following the backing track or a tap-started clock), **manually**, or **assisted** (the next tone is highlighted and switches when you tap). The live guide shows the current chord as root → fifth → root and the next melody keys.
5. Refine anything: tones, layers, envelope/filter/EQ/effects, chords, melody notes, section timing. You can also **Regenerate this section** or **Restore AI Original**.

## Run it

You need a Mac with **Xcode 15+**, an iPhone on **iOS 17+**, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cd TonePilot && xcodegen generate && open TonePilot.xcodeproj
```

1. Set your signing team and bundle id.
2. Sounds: download **GeneralUser GS** from <https://github.com/mrbumpy409/GeneralUser-GS> (`GeneralUser-GS.sf2`). Put it in `App/Resources/SoundFonts/`, or import it in **Settings › SoundFonts**.
3. Run on the iPhone. The Simulator works for the UI and analysis, but has no USB MIDI.
4. Connect the Casio. Follow **Settings › Connect your Casio** and the hardware checklist.

### Tests

```bash
cd Packages/TonePilotCore && swift test     # 85 tests (macOS or Linux; Docker: swift:6.0-noble)
TONEPILOT_SF2=/path/GeneralUser-GS.sf2 swift test   # also tests the real SoundFont
cd server && pip install -r requirements-dev.txt && pytest tests   # 8 tests
```

A short audio demo rendered by the engine with GeneralUser GS (left-hand Root→Fifth→Root on piano, right-hand Bansuri-like flute with strings and celesta) can be generated with `TONEPILOT_DEMO_OUT=demo.wav TONEPILOT_SF2=… swift test --filter DemoRenderTests`.

## Project layout

```
project.yml                       XcodeGen spec (iOS 17 app + local package)
App/Sources/
  Services/AppModel.swift         Library, one-click pipeline, server upload (consented), section scheduler,
                                  accompaniment, melody/chord corrections, presets, samples, backup
  Audio/ToneEngineHost.swift      Hosts ToneEngine in AVAudioEngine (AVAudioSourceNode); audio session
  Audio/SoundEngine.swift         Legacy Apple-sampler engine (fallback)
  Audio/SectionPlayer.swift       Backing track / song clock
  MIDI/MIDIInputManager.swift     CoreMIDI (UMP), hot-plug, activity log
  Views/                          Library · Song page · Melody & chord guide · Tone Studio · Sample creator ·
                                  Performance · Settings/Diagnostics/Analysis server
Packages/TonePilotCore/           Platform-independent and fully tested
  Engine/                         SF2 parser, sampler/synth voices, ADSR, SVF filter, EQ, chorus, delay,
                                  Freeverb, limiter, sequencer, controller, instrument cache, WAV I/O
  Analysis/                       FFT, features, tempo/beats, key/chords, structure, melody extraction,
                                  chord guide, section insights, SongAnalyzer
  Arrangement/                    AutoArranger, SongPipeline
  Performance/                    Section scheduler (auto/manual/assisted), accompaniment generator
  MIDI/                           Parser, NoteRouter (layers, splits, stuck-note safety), gain staging
  Models/ Persistence/ Backend/   Data model (schema v3), library store, preset exchange, server client
server/                           Optional FastAPI server: Demucs stems + Basic Pitch vocal melody
docs/                             Capabilities, feasibility/architecture, hardware checklist
```

## Honest limitations

* **The iOS app has not been compiled in this environment** (Linux, no Xcode). Every app file passes a Swift syntax parse, and all the logic it calls lives in the tested core package. Expect to fix small compile issues on the first Xcode build. The Casio workflow is **not complete until the hardware checklist passes**.
* Instrument recommendations are evidence-based rules over measured sound character, melody and (optionally) stem levels. They are **not** a trained instrument classifier, and no claim is made to reproduce a composer's exact studio sounds.
* Demucs separation is integrated on the server but **was not run here**: its model weights couldn't be downloaded. Basic Pitch **was** run.
* The melody guide plays note pitches. Ornament bends are shown on screen but not yet replayed by the guide voice.
* Analysis on dense film mixes is approximate. Every estimate shows a confidence level and can be corrected.
