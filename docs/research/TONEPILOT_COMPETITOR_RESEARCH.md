# TonePilot — Competitor Research (Phase A)

**Date:** 2 November 2026 (IST). **Status:** research and documentation only. No app code, models or CI were changed for this.

## How this research was done, and its limits

- **No hands-on testing.** Nothing here comes from using the apps. Every statement comes from public information.
- **Direct page fetches were blocked.** This cloud session's network policy blocks moises.ai, forge.dwave.cc, ototheory.com, yamaha.com, chordai.net and others. Evidence comes from web-search results: App Store / Google Play listings, official pages as indexed, vendor blogs, and third-party reviews.
  - Each claim carries its source and one of these evidence levels:
    - **D** = documented by the company (official page, store listing, official blog or help centre);
    - **R** = reported by a third party (review, press);
    - **I** = our inference;
    - **U** = unverified (claimed somewhere, not confirmed).
  - To verify against live pages, allow these hosts in the session's network settings, or check them by hand.
- **A missing feature is not proof of absence.** "Not documented" means we found no public statement either way.
- **Prices change.** Figures are as reported on the access date. Re-check before relying on them.

## 1. Primary competitors

### 1.1 Moises (Moises Systems) — iOS · Android · Web · Desktop

- **Target users / use:** musicians practising along with songs: separate, slow down, transpose, loop.
- **Stems (D):** vocals, drums, bass, guitar, piano, strings, "other" ([App Store](https://apps.apple.com/app/id1515796612)).
  - Premium adds finer splits: lead vs rhythm guitar, acoustic vs electric guitar, main vs background vocals (R/D, search summary of [moises.ai features blog](https://moises.ai/blog/latest/moises-features)).
- **Chords (D):** three difficulty levels (easy, medium, advanced), synced to bars and beats.
- **Key and BPM (D):** key detection with chords transposed to all 12 keys; BPM detection; speed changer.
- **Sections (D):** navigate and loop song sections, including on trimmed tracks.
- **Smart metronome (D):** a click track that follows the song's beat.
- **Setlists (D):** listed among the free features (R; plan details vary between sources).
- **Free tier (D, App Store):** a monthly separation cap and a shorter file-length limit; vocal, drum and bass separation, chords, metronome, pitch shift, BPM and setlists listed as free (R). **Exact limits: U** (sources disagree).
- **Processing (I):** cloud separation is likely given the web app and per-month caps; not confirmed for on-device. **Offline: U.**
- **MIDI / keyboard integration:** not documented.
- **Takeaway:** the strongest reference for song import → practice workspace → section looping. Its moat is separation quality and polish, which is expensive to compete on.

### 1.2 Muse Forge (DeepWave) — iOS · Android · Web

- **Stem separation (D):** vocals, drums, bass "and more"; usually finishes in a minute or two; stems can be soloed or muted; MP3 downloads, lossless WAV on paid plans ([feature page](https://forge.dwave.cc/en-US/features/stem-separation)).
- **Piano transcription, "PopPianoAI" (D):** analyses melody, harmony and rhythm, then produces a playable piano arrangement with chord symbols and an audio rendition ([blog](https://forge.dwave.cc/en-US/blog/1356)).
  - Piano sheet music is listed as free and outside the shared allowance ([Google Play](https://play.google.com/store/apps/details?id=com.dwave.museforge&hl=en_US)).
  - **Important:** it is a piano *arrangement* (a reduction), not a reconstruction of each original instrument part. Instrument-by-instrument reconstruction is **not documented**.
- **One-step templates (D):** e.g. remove vocals → piano score of the accompaniment → PDF and MIDI downloads.
- **Chord recognition (D):** guitar and ukulele chord blog ([blog](https://forge.dwave.cc/en-US/blog/1359)).
- **Text-to-music generation (D):** shares a monthly allowance with separation and chord recognition.
- **Limits (D):** 100 MB uploads; MP3, WAV, FLAC or a link.
- **Export:** PDF, MIDI (D); MusicXML (U; mentioned in our brief, not confirmed in the results we found).
- **Processing (I):** cloud (allowances, link uploads). **Offline: U.**
- **Takeaway:** its pipeline (separate → chords → piano arrangement → export) is the closest published "song → playable keyboard part" flow. Its piano reduction quality on dense Indian orchestration is unknown, and is worth a hands-on test with lawful audio.

### 1.3 OtoTheory (Norito Harada) — iOS · Web

- **Chord detection from audio or a recording (D),** with user correction of anything the detection missed ([store listing mirror](https://mwm.ai/apps/ototheory-chord-progression/6755084287)).
- **Chord shapes (D):** fretboard and keyboard views highlighting chord tones in real time.
- **Grooves and presets (D):** drum parts export on separate tracks (kick, snare, hi-hat, each percussion).
  - **Groove count is contradictory.** Our brief says 19 grooves; the listing says Pro adds "38 more grooves". The free and total counts are unverified.
- **Multi-track MIDI export (D):** chord track, guide tones, bass track and section markers; tested in Logic Pro, Cubase and Ableton Live (per the listing).
- **Pricing (D):** free with a cap on chord detection; Pro adds unlimited saves, iCloud sync, more grooves, and MIDI and audio export.
- **On-device analysis: U.** Our brief says on-device, but none of the sources we found confirm it. **Manual beat/tempo correction: U** (in the brief; not confirmed here).
- **Takeaway:** the closest reference for a chord player plus groove-based backing UI and MIDI export. Its backing is generic grooves over progressions, not the original song's patterns (I, from the documented features).

### 1.4 Yamaha Chord Tracker — iOS · Android

- **Analyses songs in the device library and shows the chord sequence (D)** ([Yamaha AU features](https://au.yamaha.com/en/products/musical_instruments/pianos/apps/chord_tracker/features.html), [Yamaha UK](https://uk.yamaha.com/en/musical-instruments/keyboards/products/apps/chord-tracker/)).
- **Melody suppressor (D):** reduces the melody (lead vocal and/or lead instrument) so the user plays it ([Yamaha Hub](https://hub.yamaha.com/keyboards/k-how-to/chord-tracker-and-the-sonogenic-keytar-part-1-the-software/)).
- **Key, tempo and chord editing (D,** per the brief and Yamaha pages).
- **Sends chord information to the instrument (D),** to play along using the keyboard's own styles (R: [American Songwriter](https://americansongwriter.com/gear-review-yamaha-chord-tracker/)).
  - It can also send the song audio to the instrument's speakers (D).
  - It connects through Yamaha's wireless adapter or Bluetooth on supported models (R). **Compatible instrument list: U** (Yamaha "Related Products").
- **Limits (D):** no DRM-protected tracks; no streaming services (Apple Music etc.).
- **Takeaway:** **proof that "phone as keyboard companion" already exists.** TonePilot must not claim phone-to-keyboard connection as its innovation. The opening is the Casio, Indian film-music-aware arrangements, and playable song-specific tones.

### 1.5 Chord AI (Nomad AI OÜ) — iOS · Android

- **Chord recognition, key, beat and downbeat (D)** ([App Store](https://apps.apple.com/app/1446177109)).
- **Real-time chord recognition from the microphone (D).**
- **Stems (D):** 4 (bass, drums, vocals, other); a newer release note mentions 4 or 6 stems and stereo stem export.
- **Audio-to-MIDI (D):** built on Spotify's Basic Pitch (the same open model TonePilot has evaluated).
- **Input (D/R):** local files, the microphone; YouTube and SoundCloud are mentioned by aggregators (R). TonePilot must not copy the YouTube route; it is excluded by project rules.
- **Offline: U.** **Pricing:** subscription (figures vary; U).
- **Takeaway:** a good reference for live chord display and chord presentation, and evidence that open models (Basic Pitch) are used in shipped products.

## 2. Technical and workflow references

### 2.1 RipX DAW (Hit'n'Mix) — desktop, paid

- **Separation (R/D):** 6+ stems or instruments, each mutable, soloable and exportable.
- **Note-level editing (R):** stems split further into editable notes, chords and unpitched sounds.
- **Instrument replacement (R):** in the base version, per reviews and the launch announcement.
- **Price (R):** about $99 base and $198 Pro, one-time per most sources ([Sound On Sound](https://www.soundonsound.com/news/hitnmix-release-ai-powered-ripx-daw), [Equipboard](https://equipboard.com/items/hit-n-mix-ripx-daw)). One directory says "$99/month", which is probably an error.
- **Takeaway:** the reference for note-level editing and sound replacement, relevant to Instrument Maker's "replace this part with a playable tone". **Not a dependency** under the zero budget.

### 2.2 BandLab and BandLab Splitter — iOS · Android · Web

- **Free Splitter (D):** 2 stems (vocals + other) or 4 (vocals, bass, drums, other), up to 2 splits a day ([BandLab blog](https://blog.bandlab.com/best-stem-separation-software-comparison-bandlab/), [help centre](https://help.bandlab.com/hc/en-us/articles/16560236938777-What-is-Splitter)).
- **Membership (D):** 6- or 7-stem separation including guitar, piano and strings (sources disagree on 6 vs 7), a drum splitter, and **stems → editable MIDI** ([membership](https://blog.bandlab.com/bandlab-membership/)).
- **Studio (D):** stems open directly in the multitrack Studio, or download as a zip.
- **Takeaway:** the reference for track rows, the mixer and a "stems → workspace" handoff.

### 2.3 Steminize (Gerschwin/steminize) — desktop/web, pre-release

- **Demucs-based separation on the user's machine (D/R):** vocals, drums, bass, guitar, piano.
- **Chord timeline (D,** v0.9.4 release notes): beat boxes scrolling with the music, bar numbers, click to jump or loop, "Simple" major/minor switch, guitar/ukulele/piano diagrams, user correction ([releases](https://github.com/Gerschwin/steminize/releases)).
- **Accuracy (D):** the maintainer calls chord detection a first draft at about **60–75% accurate**. That is an honest benchmark statement worth copying in spirit.
- **Basic Pitch use: U** (in our brief; not confirmed in release notes). **Licence: U.** Repository access was blocked from this session; check before reusing any code.
- **Takeaway:** an architecture reference for combining open models locally (the same philosophy as TonePilot). Its correction-first chord UI is directly relevant.

## 3. Additional references

| Product | What we can learn | Evidence |
|---|---|---|
| Piano Transcriptionist (iOS) | On-device piano audio → editable MIDI and sheet music; best on solo piano, accuracy drops with other instruments; velocity refinement from the audio | D, [App Store](https://apps.apple.com/app/id6456886504) |
| Piano Transcriber (iPad, free, open source) | On-device ML transcription, piano only | D, [App Store](https://apps.apple.com/us/app/id6504340213) |
| Tunorum | **Not found.** No public listing was found under this name; the name may be misspelled | U |
| Apple Music Memos | Chord detection in recordings, about 50–75% on simple chords per one user; **discontinued in March 2021** | R, [Digital Music News](https://www.digitalmusicnews.com/2021/03/02/apple-retires-music-memos/) |
| Chord Rhythms | **Not found** under this name. Similar apps: Chordi (USB MIDI in/out, arpeggiator and strummer modes), Chord Studio (real-time chord recognition while playing, MIDI keyboard) | U / D ([Chordi](https://apps.apple.com/us/app/-/id6740488017), [Chord Studio](https://apps.apple.com/ge/app/chord-studio/id6749439732)) |
| MuseScore | Notation editing and MIDI handoff | Known product; not researched in depth here |
| **Casio's own apps** | "Chordana Play" functions have moved into **CASIO MUSIC SPACE**, which connects to the **CT-S and LK-S series only**; CTK/LK users keep Chordana Play. **The CT-X series is not named** ([Casio notice](https://web.casio.com/app/en/play/top.html)) | D |

**Casio CT-X870IN facts (R, retailer listings):**
- 61 touch-response keys;
- 48-note polyphony;
- USB terminal;
- plays SMF 0/1 and CASIO MIDI files from a USB flash drive.

**Whether its USB is class-compliant MIDI is not confirmed by Casio documentation** (TonePilot's hardware checklist already treats it as needing a test). Casio's current app does not appear to support this model, which looks like a real gap for CT-X owners (I).

## 4. Competitor comparison matrix (publicly documented capabilities; not hands-on accuracy)

Key:
- **●** full support, documented;
- **◐** partial support;
- **ND** not documented (absence not proven);
- **NA** not applicable;
- **U** claimed but unverified.

| # | Capability | Moises | Muse Forge | OtoTheory | Yamaha CT | Chord AI | RipX | BandLab | Steminize | **TonePilot today** |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Song import (local file) | ● | ● | ● | ● (no DRM) | ● | ● | ● | ● | ● |
| 2 | Audio separation | ● (7+) | ● | ND | ◐ (melody suppressor) | ● (4/6) | ● (6+) | ● (4 free / 6–7 paid) | ● | ● (Demucs 4/6-part, on-device; personal build only, see licences) |
| 3 | Instrument identification | ◐ (stem classes) | ND | NA | NA | ND | ◐ (per-instrument separation) | ◐ (stem classes) | ◐ (stem classes) | ◐ (Apple classifier in production; EfficientAT research) |
| 4 | Instrument-role identification | ND | ND | NA | ◐ (melody vs rest) | ND | ND | ND | ND | ◐ (lead/backing split; roles in core) |
| 5 | Melody extraction | ND | ● (inside the piano arrangement) | ND | ◐ (suppression only) | ◐ (audio-to-MIDI) | ● | ◐ (MIDI, paid) | U | ● (melody guide) |
| 6 | Chord detection | ● | ● | ● | ● | ● | ● | ND | ● (~60–75% self-reported) | ● (maj/min + hypotheses in core) |
| 7 | Beat tracking | ● | ● | U (manual correction) | ● (tempo) | ● | ND | ND | ● | ● (DP; Beat This! evaluated, not adopted) |
| 8 | Section detection | ● | ND | ● (MIDI markers) | ND | ND | ND | ND | ND | ● |
| 9 | Piano transcription | ND | ● | NA | NA | ◐ (Basic Pitch) | ◐ | ◐ | U | ND (not a goal) |
| 10 | Note-level editing | ND | ND | NA | NA | ND | ● | ◐ (MIDI) | ND | ND |
| 11 | Custom tones | NA | NA | NA | ◐ (keyboard's own voices) | NA | ◐ (replacement) | ● (virtual instruments) | NA | ● (8-layer tones, SF2/samples, Tone Studio, ToneMatcher) |
| 12 | Arrangement reconstruction | ND | ◐ (piano reduction) | NA | NA | ND | ◐ (notes per stem) | ND | ND | ◐ (Song Arpeggio patterns learned per section) |
| 13 | Accompaniment generation | ND | ◐ (generation from text) | ● (grooves) | ● (via keyboard styles) | ND | ND | ◐ (loops) | ND | ● (AutoArranger; no-fill classifier in core) |
| 14 | Song-specific arpeggios | ND | ND | ND | ND | ND | ND | ND | ND | ● (learned patterns + live fill) |
| 15 | MIDI input | ND | ND | ND | NA | ND | ND | U | ND | ● (CoreMIDI, USB) |
| 16 | MIDI output / export | ND | ● (export) | ● (export) | ◐ (chords to Yamaha) | ◐ (export) | ● | ● (paid) | U | ND (no MIDI out to the Casio; audio out instead) |
| 17 | External keyboard connection | ND | ND | ND | ● (Yamaha only) | ND | NA | ◐ | NA | ● (Casio over USB MIDI in; audio to AUDIO IN) |
| 18 | Offline operation | U | U (cloud likely) | U | ● (I: local analysis) | U | ● (desktop) | ND | ● | ● (on-device by design) |
| 19 | iPhone support | ● | ● | ● | ● | ● | NA (Vision Pro, desktop) | ● | NA | ● (primary) |
| 20 | Free / open-source | ◐ freemium | ◐ freemium | ◐ freemium | ● free (I) | ◐ subscription | ○ paid | ◐ freemium | ● open source (licence U) | ● personal, no cost |

The TonePilot column reflects the repository on 2 Nov 2026. See the gap analysis §2 for evidence and validation status. Several "●" entries are implemented but **not validated on real Indian film songs**.

## 5. Contradictions and unknowns flagged (not silently resolved)

1. **OtoTheory groove count:** 19 (brief) vs "38 more" with Pro (listing). **On-device analysis and beat correction:** unverified.
2. **Muse Forge MusicXML export:** in the brief; not found in the sources we saw.
3. **Moises free-tier limits** differ between sources.
4. **BandLab paid stems:** 6 vs 7.
5. **Steminize Basic Pitch use and licence:** unverified (repository blocked from this session).
6. **"Tunorum" and "Chord Rhythms":** no public listing found under these names.
7. **Yamaha compatible-instrument list** and connection method per model: not retrieved.
8. **Inside TonePilot:**
   - `docs/CAPABILITIES.md` is stale: it says 118 Swift tests, while the current build runs 224. It has not been edited here; flagged for update.
   - `PROJECT_MEMORY.md` §1 records the owner's earlier definition, "instrument recognition and tone matching are secondary" to accompaniment reconstruction. The newer strategy (and this brief) makes the Instrument Analyser a P1 differentiator. The owner should confirm which framing governs.

## 6. Source register (all accessed 2 Nov 2026 via web search; direct fetch blocked)

| Product | Source |
|---|---|
| Moises | https://apps.apple.com/app/id1515796612 · https://moises.ai/blog/latest/moises-features |
| Muse Forge | https://forge.dwave.cc/en-US · https://forge.dwave.cc/en-US/features/stem-separation · https://forge.dwave.cc/en-US/blog/1356 · https://forge.dwave.cc/en-US/blog/1359 · https://play.google.com/store/apps/details?id=com.dwave.museforge |
| OtoTheory | https://mwm.ai/apps/ototheory-chord-progression/6755084287 · (https://www.ototheory.com/ — blocked) |
| Yamaha Chord Tracker | https://au.yamaha.com/en/products/musical_instruments/pianos/apps/chord_tracker/features.html · https://uk.yamaha.com/en/musical-instruments/keyboards/products/apps/chord-tracker/ · https://hub.yamaha.com/keyboards/k-how-to/chord-tracker-and-the-sonogenic-keytar-part-1-the-software/ · https://americansongwriter.com/gear-review-yamaha-chord-tracker/ |
| Chord AI | https://apps.apple.com/app/1446177109 |
| RipX DAW | https://www.soundonsound.com/news/hitnmix-release-ai-powered-ripx-daw · https://equipboard.com/items/hit-n-mix-ripx-daw · https://www.digitaldjtips.com/ripx-daw/ |
| BandLab | https://blog.bandlab.com/best-stem-separation-software-comparison-bandlab/ · https://help.bandlab.com/hc/en-us/articles/16560236938777-What-is-Splitter · https://blog.bandlab.com/bandlab-membership/ |
| Steminize | https://github.com/Gerschwin/steminize/releases |
| Piano Transcriptionist / Transcriber | https://apps.apple.com/app/id6456886504 · https://apps.apple.com/us/app/id6504340213 |
| Music Memos | https://www.digitalmusicnews.com/2021/03/02/apple-retires-music-memos/ |
| Chordi / Chord Studio | https://apps.apple.com/us/app/-/id6740488017 · https://apps.apple.com/ge/app/chord-studio/id6749439732 |
| Casio apps | https://web.casio.com/app/en/play/top.html |

## 7. Recommended hands-on test protocol (for the owner; not performed)

Use the **same small set of lawful audio** in every app. Use owner recordings or properly licensed clips, and do not upload copyrighted songs to cloud services unless their terms and your rights allow it.

For each app, record:
- output;
- processing time;
- manual corrections needed;
- device and app version;
- free or paid tier;
- online or offline.

Cases to try:

| Case | What to observe |
|---|---|
| Dense orchestral section | Are overlapping instruments separated? |
| Flute + violin passage | Are both isolated and identified? |
| Indian percussion | Is tabla, mridangam or dholak named? |
| Fast melody | Are the notes and timing accurate? |
| Chord change | Is the right chord detected on the right beat? |
| Section boundary | Is the intro/interlude/chorus edge found? |
| Arrangement | Does the app give playable parts, or only audio stems? |
| Keyboard | Can it take MIDI from, or play through, an external keyboard? |
| Offline | What still works in flight mode? |

Suggested shortlist:
- Moises, Muse Forge, OtoTheory, Yamaha Chord Tracker (analysis only; no Yamaha keyboard), Chord AI and Steminize.
- RipX only via its trial, if one is available.
