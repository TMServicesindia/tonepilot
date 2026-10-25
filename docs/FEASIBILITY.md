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
| **AVAudioUnitSampler** (Apple) | SF2/DLS/EXS/AUPreset playback | **Used.** Note: program/bank must match the SF2. The melodic bank MSB is `0x79`, percussion `0x78`. |
| **GeneralUser GS** SoundFont | 259 GM-style presets, ~30 MB | License v2.0 allows private/commercial music use and use in software. The author can't fully verify sample origins, so review before shipping on the App Store. Not bundled in the repo; the user installs it. |

## 3. Architecture

```
┌──────────────── iPhone app (SwiftUI) ────────────────┐
│ Library · Analyse · Tone Studio · Perform · Settings │
│                    AppModel (@MainActor)             │
│      │ saves (debounced)       │ activate(tone)      │
│ LibraryStore (JSON + files)    ▼                     │
│                     NoteRouter (lock, no alloc spikes)│
│ Casio ─USB MIDI─▶ MIDIInputManager ─events─▶ │       │
│   (CoreMIDI thread, UMP MIDI 1.0)       SoundCommands│
│                                              ▼       │
│     SoundEngine: sampler→EQ→delay→reverb→mixer ×6    │
│                  → tone bus → peak limiter → output ─┼─▶ 3.5 mm → Casio AUDIO IN
│     SectionPlayer (song playback, loop) ─────▲       │
│ Analysis (background Task): decode → TonePilotCore   │
│   features → tempo/beats → key → chords → sections   │
│   → tone suggestions → Song.apply (keeps user edits) │
└──────────────────────────────────────────────────────┘
        (Milestone 4: optional Mac/server job: Demucs + Basic Pitch → same result types)
```

* **TonePilotCore** (Swift package, no Apple-only frameworks) holds the models, versioned persistence and migrations, MIDI parsing/routing, all analysis DSP and the suggestions. It builds and tests on Linux CI as well as on Xcode.
* **Real-time rules:** the MIDI callback only parses, routes and calls `startNote`/`stopNote`. Preset loading runs on a background queue. Analysis runs in detached tasks. Nothing ever runs on the render thread except Apple's own nodes.
* **Analysis interface:** the analysers produce `SongAnalysisResult`. A future server or Demucs backend returns the same type, so the UI doesn't change.

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

## 6. Phased plan

| Milestone | Scope | Status |
|---|---|---|
| 1. Foundation | SwiftUI app shell, library, models, persistence, MIDI input + diagnostics, sampler playback, MP3 import | **Built** (this repo) |
| 2. Layered tones | 6-layer engine, splits/velocity layers, limiter/meter, audition | **Built.** Needs on-device verification |
| 3. Preset library | Patch editor incl. envelopes, user samples (SFZ/WAV multisample), preset import/export | Partly built: layer editing, effects, save/load. Envelopes and user samples are not built. |
| 4. Song analysis | On-device tempo/beats/key/chords/sections ✅. Stems (Demucs) and transcription (Basic Pitch) on a Mac/server or Core ML ⏳ | On-device part **built and tested** |
| 5. AI tone suggestions | Heuristic suggestions ✅. Model-based instrument tagging on stems ⏳ | Heuristic only |
| 6. Performance mode | Playlists, section buttons, layer mutes, master, panic | **Built** |
| 7. Quality | Latency/CPU profiling, layer-count limits, interruption/route tests, crash recovery | Not started (needs device) |

## 7. Milestone 1 files

See [README.md](../README.md#project-layout).
