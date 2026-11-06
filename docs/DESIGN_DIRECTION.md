# TonePilot — design direction v2 (identity, imagery, hierarchy)

*6 Nov 2026 · owner: "think more on UI; take the competitors as inspiration; unique, easy to understand; icons, images; better visual hierarchy". Builds on the locked brief (`UX_COMPETITIVE_RESEARCH.md`); nothing here changes those decisions.*

## 1. What makes TonePilot unique: three signature elements

Competitors decorate with stock photos (sample packs) or generic gradients. TonePilot's identity instead comes from **what it knows about each song**. Three elements appear consistently across the app, each derived from real data.

### A. Song Map ("song DNA")

The song's structure drawn as a ribbon:
- one block per section;
- width = length, height = energy (from the analysis);
- colour = repetition group (repeats share a colour);
- a ★ on the hook.

**Uses:**
- **Song artwork:** replaces the initials tile. Every song gets a unique, meaningful cover generated on the phone; no copyrighted album art.
- **Play page:** the large, tappable timeline with the playhead.
- **Song rows:** a small thumbnail.

**Inspiration:** Moises's synced timeline and Apple Music's generated covers, but data-driven: you see the shape of a song (quiet intro, big chorus, BGM hook) before pressing play.

### B. Instrument tiles (TonePilot's own illustrations)

An original set of duotone instrument illustrations (strings, flute / bansuri, piano, guitar, veena / sitar, tabla, drums, bass, voice, brass, bells, synth, pad):
- drawn for TonePilot, so there are no licensing questions;
- shipped as vector assets, so they work on Android too;
- each sits on a tile tinted by its family colour.

**Uses:** tones, layers, parts in the mixer, and the sound browser grid.

**Inspiration:** GarageBand's sound tiles and Logic's plug-in tiles. A tone made of strings + slow strings shows as two overlapping tiles: you see the sound.

### C. Keys guide

A small 61-key Casio keyboard strip that lights the keys to press (the left-hand chord and the next melody note) in the same colours as the chord card.

**Inspiration:** Yamaha Chord Tracker's keyboard diagrams, applied to the owner's actual keyboard. It turns "Em — E·B·E" into something you can glance at mid-song.

## 2. Visual hierarchy rules

Each screen has exactly three levels.

| Level | What | How it's shown |
|---|---|---|
| **1 — Now** | The one thing the screen is about: the section playing, the suggested tone, the song to continue | Largest type (display / title), the only accent-filled element, top of the screen |
| **2 — Context / next** | What comes next, why, alternatives | Headline / body, instrument tiles and the song map, secondary buttons |
| **3 — Details** | Numbers, settings, sources | Caption / metadata, disclosure rows, info sheets |

- **One accent.** Amber marks only the level-1 action or the current selection on a screen; everything else is neutral.
- **Imagery in content only** (tiles, song map), never in chrome (bars, buttons), so the interface stays calm.
- **Icons label every page and row** (SF Symbols in the app). Icon plus text, never icon alone, except the transport.
- **Distance legibility (Play page):** the section name and chord at display size; nothing important under footnote size.

## 3. Screen-by-screen thinking

| Screen | Level 1 | Inspiration → TonePilot twist |
|---|---|---|
| **Songs** | "Continue" card: the last song's map art + Play | Apple Music "Continue listening"; the cover is the song map |
| **Analysis** | A step strip: Beat → Key & chords → Sections → Parts → Tones, each with an icon that fills as done | Moises's processing wait, made informative: results appear step by step and you can play as soon as the beat is found |
| **Play** | Section now (display), chord now with the keys guide | MainStage Perform mode (calm, big) + Chord Tracker keys |
| **Mix** | Parts as instrument tiles with live level bars | Moises mixer; tiles make parts recognisable without reading |
| **Tone** | The suggested tone as overlapping instrument tiles + Use / Change / Compare | Logic plug-in tiles + "suggest then refine" |
| **Sound browser** | Suggested-for-this-section row, then a family grid of tiles | GarageBand Sound Library tiles + Logic filters |
| **Tone editor** | The selected layer's tile with its 3 key controls | Logic Details view behind tiles; Koala's few-controls-first |
| **Settings** | Grouped rows with coloured icon squares (iOS Settings idiom) | Native familiarity |

## 4. Motion and feedback (in the app)

- **Section change:** the section name cross-fades, never slides, so there's no motion while you play.
- **Analysis steps:** each icon fills with a short check animation (off with Reduce Motion).
- **Audition (▶ on any tile):** the tile shows a small level ring while it plays.
- **Haptics:**
  - light tap on segment change;
  - success haptic when a suggestion is accepted or a pack finishes downloading.

## 5. What we deliberately don't do

- **No stock photos or album art:** licensing, and they say nothing about the song.
- **No glow waves or decorative gradients in chrome.** Subtle family tints appear only on instrument tiles.
- **No icon-only controls** except the universally understood transport.
- **No layout motion during playback** (CLAUDE.md smoothness rules).

---

# v3 — "crazy" round: best-in-class per feature, then go further

*Owner, 6 Nov: "more crazy — think who is best in each feature, how they designed the screen, and ideate." Each idea starts from a documented best-in-class pattern (public sources, not hands-on) and adds what only TonePilot can do: it knows every song's sections, chords, parts and tones. All of it is drawable in SwiftUI (`Canvas`, `TimelineView`, observing `LiveState` in small views) at 60 fps; feasibility notes are below.*

| Feature | Best in class (why it works) | TonePilot's crazy version |
|---|---|---|
| **Home** | Spotify / Apple Music: one giant hero, then horizontal shelves; artwork carries the emotion | **Song Aura hero:** the last song's real waveform drawn as a glowing aura in its section colours, then shelves ("Ready to play", "Needs a tone", "Tamil"), each card with its Song Map cover |
| **Analysis** | Shazam: the pulsing button turns waiting into anticipation. Moises: a simple progress state | **Discovery scan:** a light beam sweeps the waveform, sections light up behind it, and every instrument it finds pops in as a tile ("Found: strings · flute · tabla"), so waiting becomes a reveal |
| **Play / perform** | Synthesia / Simply Piano: falling notes onto a keyboard, readable without music reading. MainStage: calm full-screen perform mode | **Note highway onto your Casio:** left-hand chord blocks (amber) and melody notes (teal) fall onto a keyboard strip matching the CT-X870IN's keys, with the section lane on top and the hook ★ glowing as it approaches. Section name huge, transport minimal |
| **Mix** | Koala / Ableton Note: big touch pads you hit without looking. djay: glowing level rings | **Stage pads:** each part is a large pad with its instrument art and a live level ring. Tap = mute ("You play this"), swipe up / down = volume, long-press = solo |
| **Tone** | Native Instruments / Spitfire LABS: every instrument has hero artwork and a few big macro knobs. Logic: plug-in tiles | **Tone card with a match radar:** hero instrument art, and a radar (bright, warm, attack, sustain, vibrato, width) that overlays *the song's part* (outline) on *your tone* (filled), so you can see why it matches and what's off. Layers stack like Wallet cards |
| **Sound browser** | Splice: waveform previews, tags, instant audition. Spitfire LABS: beautiful cards | **Audition deck:** the closest sound as a big card with a match bar, playing the song's own melody. Swipe left = next closest, swipe right = use, ▶ = replay. Grid view for browsing by family |
| **Arpeggio** | Patterning / Koala: radial step sequencers that look like instruments | **Pattern ring:** a 16-step circle; lit steps show the chord position (R · 5 · 8 · 3); a sweeping arm follows the beat; the centre shows the style and BPM |
| **Chord correction** | Chordify / Yamaha Chord Tracker: chord diagrams, pick from suggestions | **Chord wheel:** the circle of fifths with the heard chord lit and the two likeliest alternatives glowing; tap a segment to hear it on the song, then confirm |

## Imagery

- **Instrument artwork** in a richer, gradient-shaded TonePilot style:
  - original vector art, licence-free and Android-ready;
  - used big on Tone, the Audition deck and stage pads;
  - small elsewhere.
- **Glow is data:** auras, highways and rings come from the song's own audio and analysis, never decorative wallpaper. That keeps "crazy" meaningful.

## Guard rails (unchanged from the locked brief)

- **Perform stays calm in layout:** visuals move, but nothing reflows while playing.
- **Every bold control has a plain fallback:**
  - pads also have Mute / Solo in VoiceOver actions;
  - the deck has a list view;
  - the wheel has a chord picker.
- **Reduce Motion:** the highway becomes a static now / next view; the scan becomes a progress list.

---

# v4 — usability first, calm colour (owner, 6 Nov: "too colourful; I don't feel the usability — don't compromise on usability")

## Usability check of the v3 ideas

| v3 idea | Usability problem | v4 decision |
|---|---|---|
| Song Aura home | Decorative; tells you nothing you can act on | **Drop.** Continue card with Play (v2) |
| Discovery scan | Pretty but hard to read progress | **Keep the idea as a clear step list** (icons + results) plus "Play now" |
| Note highway | Needs fast reading while playing; busy; a new skill to learn | **Drop for now.** Static "chord now → next" plus the keys guide (readable at a glance) |
| Stage pads | Volume by swipe is a hidden gesture; pads hide levels | **Drop.** Rows with visible sliders and labelled Mute / Solo |
| Match radar | Most players can't read a radar chart | **Replace** with a plain sentence: "Why this tone", plus one match % |
| Audition deck | Swipe-only choices are hidden and easy to trigger by mistake | **Drop.** List with ▶ and a clear "Use" button |
| Pattern ring | Hard to edit precisely on a circle | **Drop.** Linear step grid (current app), larger |
| Chord wheel | The circle of fifths intimidates non-theory users | **Drop.** Two big likely chords, then root + type |

## Calm colour rules (v4)

- **Base:** neutral near-black and greys. No violet glows, no gradients on content.
- **Amber is the only colour of action:** primary button, the current selection, the playhead and the current section.
- **Instrument art:** single-tone line drawings on neutral tiles. Recognisable by shape, not colour.
- **Song Map:** grey blocks; the current section is amber and the hook is marked ★. Repeats share a grey shade.
- **Status colours:**
  - red only for errors;
  - amber for attention;
  - success is a ✓ icon in neutral text, not green fills.

## Usability rules applied to every v4 screen

1. **One primary action per screen**, visually obvious, and reachable with the thumb.
2. **Visible controls:** no hidden gestures; every action has a labelled button.
3. **Touch targets ≥ 44 pt;** body text ≥ 15 pt; the Play page readable from the keyboard (section 40 pt+, chord 40 pt+).
4. **Plain words**, no theory or engine jargon on main screens.
5. **Always know where you are:** song name, page and section always visible in Play.
6. **Native iOS patterns:** navigation bar, sheets, lists, segmented control and tab bar.


---

# v6 — v5 layout and usability + colour from v2 / v3 (owner, 6 Nov: "colours went too dull; combine v2 and v3")

- **Layout, controls and usability rules:** unchanged from v5 / the screen spec.
- **Colour returns where it identifies something:**
  - **Instrument tiles:** family-tinted (strings warm brown, winds teal, keys indigo, plucked rose, percussion bronze, voice plum, bass violet, synth blue, brass gold), with v3's shaded instrument art.
  - **Song Map:** repeats in teal / indigo / pink / grey; the current section amber with a soft glow.
  - **Parts:** coloured dots and coloured level bars.
  - **Settings and Details rows:** coloured icon squares by group (iOS Settings idiom).
  - **Status:** success in green (✓ Ready, finished analysis steps).
  - **Keys guide:** left hand amber, next melody note teal.
- **Light:** primary buttons, the play button and the selected page carry a soft amber glow; a faint violet / warm ambient light sits behind each screen; the Tone suggestion card has a warm tint.
- **Still not allowed:** glowing cards everywhere, colour as the only signal, decoration in bars and navigation.


## v9 — song covers (owner, 6 Nov)

The file's own artwork first. Otherwise a generated cover:
- **D2 "Ring over Aura"** for large covers;
- **D3 "Halo"** for small ones.

Explorations: `design/mockups/v7-covers`, `v8-covers`. The full set with covers: `design/mockups/v9`.
