# TonePilot — Feasibility, Research & Architecture

_Last researched: October 2026._

## 1. Feasibility assessment

| Goal | Feasible? | How | Main risk |
|---|---|---|---|
| Play app-generated tones from the Casio's keys | **Yes** | Casio USB TO HOST is class-compliant USB MIDI. iOS Core MIDI reads it through Apple's USB camera adapter (Lightning) or USB-C. | Some adapters/phones don't power the device: use a powered adapter or hub. |
| Hear those tones through the Casio speakers | **Yes, with a second cable** | iPhone audio out → 3.5 mm stereo cable → Casio **AUDIO IN** (stereo mini jack, ~200 mV sensitivity per retailer specs). | Lightning iPhones have one port. Getting MIDI in **and** audio out needs a powered hub plus a USB audio interface or DAC. USB-C iPhones: a USB-C hub with a 3.5 mm jack. |
| Layered/split tones (piano + strings + bell) | **Yes** | `AVAudioUnitSampler` × N with SF2 presets, per-layer filter/delay/reverb/pan/volume, peak limiter. | CPU per layer. Capped at 6 until profiled on a real device. |
| Import MP3 and analyse on-device | **Yes** | AVFoundation decodes MP3. Pure-Swift DSP estimates tempo, beats, key, chords and sections. | Accuracy on dense film mixes. Every result is labelled as an estimate and can be corrected. |
| Analyse from a YouTube link | **No (by design)** | YouTube's terms prohibit downloading audio or separating/isolating it. We store the link as a reference only. | — |
| Analyse songs from streaming subscriptions | **Yes, via Listen Mode** | Spotify's audio-analysis API is closed to new apps (Nov 2024) and Apple MusicKit gives no raw audio, so TonePilot listens through the microphone while the user's app plays (the approach apps like Chord ai use), keeps only derived data and discards the audio. | Lower accuracy than a clean file; no automatic song-position sync during performance (timer/assisted switching instead). |
| Identify the exact instruments in a mix | **Partly, later** | Needs stem separation (Demucs) plus instrument tagging. Today: rules over brightness, attack and sustain, labelled as heuristics. | Demucs is a large PyTorch model, so it's realistic on a Mac or server, not on the phone. |
| Recreate the exact studio sound | **No** | The best we can honestly offer is the closest achievable approximation: suitable presets, layering and effects. | Must not over-promise. |

**Verdict:** the core idea (Casio keys → custom layered tones → Casio speakers, organised per song section) is fully buildable now. The "AI" layer starts as transparent on-device DSP. It grows into stem separation and transcription on a Mac or server once the live-playing path is proven.

## 2. Existing tools compared

| Tool | What it covers | Reuse? |
|---|---|---|
| **Moises** (app) | Stem separation, chords, key, BPM, section looping | Reference only (proprietary). Proves users want section-aware practice. |
| **Mighty Synth Sampler** (app) | SF2/SFZ, multisampling, layers, MIDI | Workflow reference only (proprietary). |
| **Pulsark** (app) | MIDI performance, sample banks | Workflow reference only. |
| **Demucs** (`adefossez/demucs`) | Stems: drums/bass/vocals/other; `htdemucs_6s` adds guitar and piano | **MIT**. The maintainer has left Meta and development is slow. The README says the 6-stem piano source "is not working great". Runs on desktop or server (PyTorch), not iOS. → Milestone 4, Mac/server. |
| **Spotify Basic Pitch** | Audio → MIDI notes (polyphonic, instrument-agnostic) | **Apache-2.0**. Ships TF, Core ML, TFLite and ONNX models, so the Core ML model can run on-device. Works best on exposed or separated parts. → Milestone 4/5. |
| **basic-pitch-ts** | TypeScript port | Not needed for a native app. |
| **AudioKit** | Synths, samplers, DSP for Swift | MIT. Not needed for Milestone 1: Apple's `AVAudioUnitSampler` loads SF2 natively. AudioKit's DunneSampler/SFZ support is a candidate for Milestone 3's custom-sample engine. |
| **AVAudioUnitSampler** (Apple) | SF2/DLS/EXS/AUPreset playback | Legacy fallback engine. Program/bank must match the SF2 (melodic bank MSB `0x79`, percussion `0x78`). |
| **GeneralUser GS** SoundFont | 259 GM-style presets, ~30 MB | License v2.0 allows private/commercial music use and use in software. The author can't fully verify sample origins, so review before shipping on the App Store. Not bundled in the repo; the user installs it. |

## 3. Architecture

```
iPhone app (SwiftUI) — Library · Song page · Melody & chord guide · Tone Studio · Perform · Settings
  AppModel (@MainActor): library, one-click pipeline, section scheduler, accompaniment, presets
    │
    ├─ Casio ─USB MIDI─▶ MIDIInputManager (CoreMIDI thread) ─▶ NoteRouter ─▶ ToneEngineController
    │                                                                              │ lock-free-for-audio
    │                                                                              ▼ command queue
    │   ToneEngineHost: AVAudioEngine ── AVAudioSourceNode ── ToneEngine.render()  (no alloc/locks/IO)
    │        8 live slots (layers) + 4 accompaniment slots (bass, drums, melody guide, click)
    │        voices: SF2/user-sample (Hermite) or synth → ADSR → SVF filter → pan
    │        slot bus: 3-band EQ → sends → chorus / delay / Freeverb → master EQ → limiter
    │        sample-accurate sequencer locked to the backing track or a tap-started clock
    │   SectionPlayer (backing track) ─────────────────────────────────┘──▶ output ─3.5 mm─▶ Casio AUDIO IN
    │
    └─ Analysis (background task): decode → SongPipeline
         features → tempo/beats/meter → key → chords(+alternatives) → melody (contour→notes, bends kept)
         → sections + activity → chord guide (Root→Fifth→Root / Sa–Pa drone) → AutoArranger
         (AI Original + My Version per section)
         optional, consented: upload → your server (Demucs stems + Basic Pitch vocal melody) → delete
```

**Engine decision.** Milestone 1 used Apple's `AVAudioUnitSampler`. It plays SF2 files, but it exposes no per-layer ADSR override or chorus, offers no sample-accurate sequencing for accompaniment, and can't be unit-tested off-device. TonePilot now renders through its own engine in `TonePilotCore`. It still **reuses the existing SoundFont assets** rather than inventing instruments; only the playback/DSP code is new. Every control is real DSP and is measured in offline tests. The Apple sampler remains selectable as a fallback. AudioKit's samplers were considered, but they can't be built or tested in this Linux environment; they remain an option if on-device profiling shows the Swift engine is too slow.

**On-device vs server.** Everything required to play runs on the phone, and so does analysis (seconds for a song). Stem separation (Demucs, PyTorch) is too heavy for a phone app, so it runs on the user's own Mac/server, only with explicit per-song consent. Basic Pitch also ships a Core ML model (`nmp.mlpackage`, ~300 KB), so on-device transcription of stems is a realistic later step.

## 4. Licensing risks

1. **YouTube:** no download or extraction. Link-only songs are marked `analysisStatus = .unavailable`.
2. **Imported audio:** the user must confirm they own the audio or are authorised to process it before analysis. It stays on the device and is deleted with the song.
3. **SoundFonts:** none are bundled in the repo. GeneralUser GS needs a sample-origin review before a commercial release.
4. **Demucs/Basic Pitch:** permissive (MIT / Apache-2.0), but model weights are large. For an App Store build, check the weights' terms and add attribution.

## 5. Hardware connection plan (CT-X870IN)

| Path | Cable/adapter | Notes |
|---|---|---|
| MIDI: Casio → iPhone | USB-A→USB-B cable + **Apple Lightning to USB 3 Camera Adapter** (active, has a power input). USB-C iPhone: USB-C→USB-B cable. | Passive OTG cables don't enable host mode. Power the adapter if the keyboard isn't detected. |
| Audio: iPhone → Casio | 3.5 mm stereo ↔ 3.5 mm stereo into **AUDIO IN**. Source: USB-C hub with a 3.5 mm jack (USB-C iPhones). On Lightning: powered USB hub on the camera adapter + a class-compliant USB audio interface or USB DAC. | Avoid Bluetooth audio (100–200 ms latency). Start at ~60 % iPhone volume. |
| Mute the Casio's own voice | Lower the keyboard's tone volume, or set Local Control off if the CT-X menu offers it. | **Unverified for the CT-X870IN.** Check the manual. Retailer listings disagree on some specs, and the official spec sheet wasn't reachable during research. |

The [hardware checklist](HARDWARE_TEST_CHECKLIST.md) is the step-by-step verification.

## 6. Phased plan (status, October 2026)

| Milestone | Scope | Status |
|---|---|---|
| 1. Foundation | App shell, library, models, MIDI, MP3 import | Built |
| 2. Sample engine & layered tones | ToneEngine, SF2, user samples, synth, 8 layers | Built and tested offline. Needs on-device profiling |
| 3. Tone Studio & presets | ADSR/filter/EQ/FX/expression, master FX, AI Original/My Version, export/import | Built |
| 4. Song analysis | Tempo/key/meter/chords/structure/melody on-device; Demucs + Basic Pitch on the server | Built; Demucs not run here |
| 5. AI arrangement | Activity, lead matching, AutoArranger, regenerate section | Built (rule-based; no trained classifier yet) |
| 6. Performance | Auto/manual/assisted switching, chord & melody guide, accompaniment | Built |
| 7. Quality | Latency/CPU on iPhone, interruption/route tests, CT-X870IN verification | **Pending hardware** |

## 7. Files

See [README.md](../README.md#project-layout) and [CAPABILITIES.md](CAPABILITIES.md).
