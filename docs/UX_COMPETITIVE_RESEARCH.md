# TonePilot — Competitive UX research

*6 Nov 2026 · Lead product design track*

## How this was researched (and its limits)

- **Sources:** public sources only — official user guides, App Store listings, independent reviews (Sound On Sound, MusicRadar, GearNews, DJTechTools, Kowatek), and user-feedback summaries. Links are at the end.
- **Not tested hands-on.** None of these apps were installed or run. This session has no iPhone or Mac UI, and casio.com is blocked here. Every pattern below is what the vendor documents or reviewers describe, not something observed.
- Where a source says nothing about a screen, this document doesn't guess.

## Comparison matrix

| Product | Strength | UX pattern worth learning | Possible TonePilot application |
|---|---|---|---|
| **Moises** (iOS) | One job done clearly: separate a song, then practise with it | Upload → wait → **mixer of parts** with mute/volume per part; chords and key synced to playback; free features first, paywall later (reviewers dislike an immediate paywall) | Song Studio's Mix page is already Moises-like. Keep the "one song, its parts, play" core front and centre; show chords synced to the playhead without extra taps |
| **GarageBand** (iOS) | Approachable entry to deep tools | **Sound browser** of large tiles, then a **Sound Library** of downloadable packs with preview and file size before download; Live Loops grid starts from a template, never empty | Sound packs: tile + preview + size + Get (TonePilot shows this today as a settings list). Tone Maker should start from the song's suggested tone (a "template"), never a blank stack |
| **Logic Pro for iPad** | Pro depth on touch without cramping | **Plug-in tiles**: each effect is a tile with its 2–4 key parameters, and a Details view for the rest. **One Sound Browser** for patches, presets, samples and loops, tap to audition, dynamic filters | Tone editor: each layer as a tile with 2–3 key controls (sound, level, brightness), "More" for envelope/filter/EQ. One sound browser with filters (family, source: built-in / sound pack / sample) and tap-to-audition |
| **Ableton Note** (iPhone) | Capture-first sketchpad | A small number of large surfaces; deep editing deliberately left to the desktop app; liked visual style, but users ask for zoomable mixer views | TonePilot is a performance companion, not a DAW: keep editing shallow on the phone, with a clear hand-off ("Edit in detail" sheets) instead of dense screens |
| **Koala Sampler** | Immediate, touch-first, "no pages of parameters" | Few controls per screen, with depth revealed only when asked; designed for touch rather than imitating hardware | Advanced controls (EQ, envelope, vibrato, key ranges) behind disclosure; the default view of each page shows only what most people change |
| **Roland Zenbeats** | Cross-platform (iOS / Android / desktop) from one product | One product across platforms, but reviews cite bugs and a UI that feels engineered rather than humane (ratings ~3.5) | Warning case: cross-platform must not mean "lowest common denominator". TonePilot's design tokens are platform-neutral, with native components per platform |
| **MainStage** (Mac) | Performance-first keyboard workflow | Three explicit modes: **Edit** (sounds), **Layout** (controls), **Perform** (full screen, minimal, follows the hardware live); the patch list order drives live switching | Separate "set up the tone" from "play the song". The Play page during playback should be a calm performance view: current section, next section, tone name, big transport |
| **Casio Music Space** | Built for the owner's own keyboards | Song list with difficulty and score per song; player with tempo, key and melody/accompaniment mute; pedal page-turn | Song rows could show useful status at a glance (analysed / separated / tone ready). Tempo/key/mute controls are familiar to Casio owners |
| **Yamaha Chord Tracker** | Chord display that's easy to read | Chords shown on a **keyboard diagram** or guitar tabs; edit a chord by choosing between two suggestions, or by root + type | Chord guide: show the chord on a small keyboard diagram; correcting a chord = pick from the analyser's top 2, then root/type |

## Best patterns, by area

- **Navigation:**
  - few top-level places (Moises, Koala);
  - Perform kept apart from Edit (MainStage);
  - deep editing as a sheet or detail view, not more tabs (Logic, Note).
- **Onboarding:**
  - start from something that already works: GarageBand templates, Moises's first separated song;
  - free value before any paywall (Moises reviews).
- **Audio analysis:**
  - one progress line naming the step in plain words, then results in place (Moises);
  - chords synced to the playhead (Moises, Chord Tracker).
- **Timeline / editing:**
  - sections as tappable blocks on a single timeline;
  - edits through suggestions first (Chord Tracker's "pick one of two").
- **Playback:**
  - large, fixed transport;
  - performance view with minimal chrome that follows the hardware (MainStage).
- **Pro interfaces:**
  - tiles with a few key parameters, plus Details (Logic plug-in tiles);
  - one unified browser with filters and audition (Logic Sound Browser).
- **Interaction:**
  - tap to audition everywhere a sound is chosen;
  - preview and size shown before any download (GarageBand Sound Library).

## Design direction for TonePilot

**"A calm instrument companion."** TonePilot sits beside a real keyboard, so the phone UI should be quiet, legible from arm's length, and fast to operate mid-song.

1. **Three places, one workspace.** Keep the three places, Songs → Play (Song Studio) → Settings, and make Song Studio one coherent workspace with a fixed transport.
2. **Suggest, then refine.** Every analysis result appears as a suggestion with one obvious way to accept or change it (hook, tone, chords, sections).
3. **Tiles, not walls of controls.** Layers and effects are tiles with 2–3 key controls, and Details for the rest (Logic).
4. **Perform mode is calm.** While playing, show the current and next section, the tone and the transport. Analysis detail stays out of the way (MainStage).
5. **Distinctive but native.**
   - Native SwiftUI components, SF Symbols and Dynamic Type.
   - The identity comes from a restrained dark palette with one warm accent (TonePilot's existing amber), a monospaced-digit time readout, and section colours that mean something.
6. **Platform-neutral tokens.** Colours, type scale, spacing, radii and motion live in one token file, so an Android (Compose) theme can be generated later without redesign (the Zenbeats lesson).

## Sources

- [Moises — App Store](https://apps.apple.com/us/app/id1515796612) · [Moises review (Violet Recording)](https://violetrecording.com/moises-review/)
- [GarageBand for iPhone User Guide (PDF)](https://help.apple.com/pdf/garagebandiphone/en_US/garageband-iphone-user-guide.pdf) · [GarageBand: Sound Library](https://support.apple.com/en-mt/102019)
- [Logic Pro for iPad User Guide — plug-ins](https://support.apple.com/guide/logicpro-ipad/lpip1cb3655f/3.0/ipados/26) · [Sound On Sound review](https://www.soundonsound.com/reviews/apple-logic-pro-ipad) · [Kowatek review](https://blog.kowatek.com/?p=29617) · [MusicRadar launch](https://www.musicradar.com/news/logic-pro-for-ipad-released)
- [Ableton Note — GearNews review](https://www.gearnews.com/?p=138117) · [Sound On Sound review](https://www.soundonsound.com/reviews/ableton-note) · [MusicTech](https://musictech.com/news/gear/ableton-note-sampler-ios-live-apple-ipad-iphone)
- [Koala Sampler — DJTechTools](https://djtechtools.com/2023/02/07/meet-the-koala-sampler-app-a-mobile-production-powerhouse-now-with-stems) · [Sound On Sound review](https://www.soundonsound.com/reviews/elf-audio-koala-sampler) · [App Store](https://apps.apple.com/gb/app/koala-sampler/id1449584007)
- [Roland Zenbeats — App Store](https://apps.apple.com/us/app/1473380367) · [MusicRadar](https://www.musicradar.com/news/rolands-new-zenbeats-app-features-tr-drum-sounds-and-makes-music-creation-easy) · [Synthtopia 3.0](https://www.synthtopia.com/content/2022/05/18/roland-zenbeats-3-0/)
- [MainStage User Guide](https://support.apple.com/en-au/guide/mainstage/mstgff038c57/mac)
- [Casio Music Space (Casio AU)](https://casioau.com/pages/casio-music-music-space) · [Yamaha Chord Tracker](https://uk.yamaha.com/en/musical-instruments/keyboards/products/apps/chord-tracker/)
