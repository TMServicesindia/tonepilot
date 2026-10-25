# TonePilot AI — capability matrix

Status key:
* ✅ **Implemented & tested**: covered by automated tests that pass. Core logic was run on Linux; on-device behaviour still needs the hardware checklist.
* 🟡 **Implemented, not yet verified on device**: iOS code written against the iOS 17 SDK but not compiled here (no Xcode on Linux; every file passes a Swift syntax parse).
* 🔶 **Partial**
* ⏳ **Planned**
* ⛔ **Blocked** (licensing, hardware or technical)

Totals: **118 Swift tests** (115 run by default; 2 need environment variables — the live server round trip and the demo render — and both passed when run) and **8 Python tests**, all passing. They include tests against the real GeneralUser GS SoundFont (287 presets) and real Spotify Basic Pitch 0.4.0.

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
| One-step MP3/M4A/WAV/AIFF import: pick a file, analysis starts automatically; title/artist from ID3 tags (v1/v2.2–2.4) or the filename; file never modified; unreadable files get a short error + Try again | ✅ core · 🟡 UI | `AudioFileTagsTests` (UTF-16 tags, v1 trailer, stripped/malformed tags) |
| Tone Selector: pick any song tone, saved tone or instrument and play it on the Casio for any music; last tone restored at launch | ✅ core · 🟡 UI | `ToneListTests` |
| Song overview: key + tonic + notes used, BPM, meter, rhythmic feel, style descriptors, bass/root movement; failed parts listed instead of guessed | ✅ | `BreakdownTests` (bass C→G→A→F recovered, straight vs shuffle, gaps reported; no BPM invented for a beatless drone) |
| Section guide: instruments heard (with %), changes from the previous section, climax, tone to use, LH pattern by tempo/feel, RH phrases, chord voicings with smooth inversions, instructions, practice steps | ✅ core · 🟡 UI | `testVoicingsUseSmoothInversions`, `testFullBreakdownFromAnalysis` |
| Practice: loop a section at 50/75/90/100% speed (pitch preserved), next/previous section | 🟡 | AVAudioUnitTimePitch; generated accompaniment pauses below 100% |
| **Listen Mode** — analyse a song playing from a licensed streaming app via the microphone; audio kept in memory only and discarded | ✅ core · 🟡 capture/UI | `ListenSessionTests` (auto-stop at song end, silence trimming, noisy capture → full pipeline at 120 ± 3 BPM). Accuracy depends on volume and room noise; stems/server are not used for captures |
| **Link → listen**: paste a YouTube/YouTube Music/Spotify/JioSaavn/Apple Music link; TonePilot fetches the public title (oEmbed), starts the mic, opens the link in its app, keeps listening in the background and builds the arrangement when the song ends | ✅ core · 🟡 app | `SongLinkTests` (service detection, oEmbed URLs, title cleanup). Live oEmbed not reachable from the build environment. **Background recording while another app plays needs device verification** |
| Direct streaming-service integration (Spotify/Apple Music audio) | ⛔ | Spotify blocked audio-analysis/audio-features for new apps (Nov 2024); MusicKit doesn't expose audio. Listen Mode is the supported route |
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
| Pitch-bend playback of ornaments in the guide voice | ✅ | Sample-accurate bend events, ±12 semitone guide range; `testMelodyGuideReplaysOrnamentBends` (A4 → +300 ct measured) |
| Cloud build of the iOS app (GitHub Actions, macOS) → unsigned `.ipa` | 🟡 written, not yet run | `.github/workflows/ios-build.yml`; needs a GitHub repo to run |

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

## 11. Android app

| Capability | Status | Notes |
|---|---|---|
| Shared Swift core on Android (engine, analysis, arrangement, library) through a JSON/C bridge | ✅ bridge · 🟡 device | `BridgeTests` (raw MIDI bytes → sound, tone selection and edits, import → analyse → sections → guide → automatic switching, unreadable-audio error, resampler). Built for arm64 with the Swift SDK for Android in CI |
| USB MIDI input (android.media.midi), hot-plug, panic on unplug | 🟡 | `MidiInput.kt` |
| Low-latency audio output (AAudio, exclusive mode when available), reopen on device change | 🟡 | `tonepilot_jni.c` |
| MP3/M4A/WAV import with the phone's decoders, Open with / Share to TonePilot | 🟡 | `AudioImport.kt` (MediaCodec → mono → resampled to 22.05 kHz in Swift) |
| Song page, section guide + practice loop (50–100%, pitch kept), Play page with live guide, switching modes, accompaniment, layer volume/octave/mute, tone list with search and My Tones | 🟡 | Compose UI; Kotlin type-checked locally, APK assembled in CI |
| Listen Mode with a microphone foreground service (works while YouTube/Spotify plays on the same phone) | 🟡 | `ListenService.kt` |
| Full Tone Studio editor, sample creator, analysis server | ⏳ | iPhone only for now |

## 12. Song Studio (iPhone)

One screen per song for playing, mixing and changing section tones. It replaces the separate Tone Studio and Play tabs; the tabs are now Library, Analyse, Studio and Settings. The full layer editor is still available from each section's **Edit sound** and from **Sound library (advanced)**.

| Capability | Status | Notes |
|---|---|---|
| Header with Play/Pause, current section and position; waveform timeline with section bands; tap/drag to seek; section chips to jump; loop the current section; practice speed 50–100% | ✅ core · 🟡 UI | `SongStudioTests.testWaveformPeaks`. Songs without a recording (Listen Mode) use the tap-started song clock |
| Mixer showing only the tracks the song really has (original recording or separated stems, rhythm, bass, background chords, AI melody, metronome, your keyboard), each labelled **Audio**, **AI notes** or **Live**; on/off, volume, solo | ✅ core · 🟡 UI | `testOnlyRealTracksAreListed`, `testOnOffVolumeAndSolo`. Your keyboard is never silenced by a solo |
| Switching a part on or off never stops the song (parts are silenced at their engine slot; the sequence keeps running) | ✅ | `testMutingAPartKeepsTheSongRunningAndKeyboardLevelIsSeparate` |
| Separate level for your keyboard | ✅ | Same test (live gain 0.25 → 0.25× level) |
| Background chords generated from the chord guide: soft pad, strings, or piano struck on each beat, voice-led close triads | ✅ | `testBackgroundChordsAreSmoothTriads` |
| **AI plays difficult parts**: the AI melody plays only in the sections you choose, with a suggested set (instrumental passages with a melody, or sections with difficult phrases) and a choice of sound | ✅ core · 🟡 UI | `testAIPlaysOnlyChosenSections` |
| Separated stems (from your analysis server) play in sync, with their own level and on/off (e.g. **Original vocals** off) | 🟡 | Started on one shared host time. Without the server, the original recording is a single audio track; stems are never presented as editable notes |
| Change a section's sound: preview on your keyboard, then **Use for <section>** (stored as that section's My Version; the AI Original and the source tone stay unchanged, and Restore AI Original still works) | 🟡 | `TonePickerSheet`, `AppModel.assignTone` |
| Edit a section's sound (layers, volume, octave, pan, effects) in a sheet while the song keeps playing | 🟡 | Reuses the existing layer editor |
| Tones change automatically at section boundaries (driven by the playback position, never by key presses), or assisted with a tap to switch | ✅ core · 🟡 UI | Existing `SectionScheduler` |
| Per-section track volumes | ⏳ | Track levels apply to the whole song. Tones and the AI melody can differ per section |
| Editing or regenerating notes of rhythm/bass/chords | ⏳ | They're regenerated from the chord guide (fix chords in the Melody & chord guide). AI melody notes can be corrected there |

## 13. Song parts — Moises-style separation on the iPhone

| Capability | Status | Evidence / notes |
|---|---|---|
| Separate a song into **Vocals, Drums & percussion, Bass, Music & instruments** on the iPhone (Demucs v4 `htdemucs` 4-source via demucs.cpp; nothing is uploaded) | ✅ engine · 🟡 iPhone | CI on Apple Silicon (`stems-bench.yml`): the app's own `StemSeparator` code separates a 50 s song with four known parts in 78 s (1.57× real time, 3 workers). Drums, bass and music land in the right files (0.79 / 1.00 / 0.95 correlation); the synthetic "voice" (a pure tone) is not recognised as vocals, real singing should be. Expect ≈6 min for a 4-minute song on an iPhone 15 |
| Runs automatically after the first analysis; progress, time left, cancel; parts saved as AAC per song | 🟡 | Blocks of 20 s with 1 s cross-faded overlaps in parallel (`StemChunkPlan`/`StemMerger`, exact reconstruction tested) |
| Parts play in sync with on/off, volume, solo; vocals off by default after separation | ✅ core · 🟡 UI | `testSeparatedDefaultsAndAIPartsFromTheRecording` |
| Re-analysis from the parts: beat from drums, chords from the instruments, melody from vocals | ✅ | `testStemsGiveCleanerChordsThanTheMix` |
| **AI plays difficult parts** from the recording itself: the original music or vocals play only in the sections you choose (or the AI melody) | ✅ core · 🟡 UI | Same test |
| Generated rhythm, bass, chords and click grouped as **AI extras**, off by default | ✅ | They are clearly labelled as not from the recording |
| Main tone (one tone for the whole song) or a tone per section | 🟡 | Main tone = the song's own tone not tied to a section |

### Separation: memory, speed and quality (measured on Apple Silicon in CI)

| | Original demucs.cpp | TonePilot build |
|---|---|---|
| Output | reference | identical (difference 123 dB below the signal, max 1.4e-6) |
| Peak memory per worker | 2,040 MB | 786 MB |
| Time, 1 worker | 3.13× the audio length | 2.27× |
| Time, 2 workers | — (doesn't fit an iPhone) | 1.34× (1.6 GB) |

The speed-ups change only how the same sums are computed: transposed convolutions without the zero-stuffed matrix (`Native/CDemucs/conv_tr_fast.inc`) and matrix products on Apple Accelerate. Earlier builds ran 4 workers at ~2 GB each, so iOS closed the app during separation. The worker count now follows the memory available (2 on an iPhone 15) and is re-checked before every block.
