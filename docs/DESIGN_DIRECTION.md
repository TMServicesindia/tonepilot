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
