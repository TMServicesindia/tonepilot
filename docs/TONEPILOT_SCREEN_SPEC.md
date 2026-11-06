# TonePilot — screen specification v1

*6 Nov 2026 · the build contract for the UX transformation.*

- **Visual reference:** `design/mockups/v4/`.
- **Tokens:** `design/tokens/tonepilot.tokens.json` / `App/Sources/DesignSystem/`.
- **Brief:** `docs/UX_COMPETITIVE_RESEARCH.md` (locked) and `docs/DESIGN_DIRECTION.md` (v4 rules).
- **Implementation:** every screen is built only from `DS` tokens and components. Every interactive element has the identifier listed here and is exercised by the speed-and-crash test or the screen tour.

## 0. Global rules

| Rule | Spec |
|---|---|
| Colour | Neutral base (Midnight #101116, Surface #1C1E25, Elevated #292C35). **Amber #FFAD32 only** for the primary action, the current selection, the playhead and the current section. Part colours only as 8 pt dots / 3 pt bars. Red only for errors |
| Type | Text styles only (Dynamic Type). Play page readouts: section `display` (≈ 40 pt+), chord `display`. Body ≥ 15 pt equivalent |
| Targets | ≥ 44 × 44 pt everywhere; the transport play button is 64 pt |
| Primary action | Exactly one filled amber button (or the transport play) per screen |
| Hidden gestures | None required. Swipe or long-press may exist as shortcuts only when a visible button does the same |
| Copy | Per `UX_COPY_AUDIT.md`: verbs on buttons, one idea per line, no engine or theory jargon on main screens |
| Motion | Cross-fades ≤ 0.25 s; none when Reduce Motion is on; no layout change while playing |
| Icons | SF Symbols with a text label; icon-only only for the transport (with VoiceOver labels) |
| Images | TonePilot's own instrument line drawings (single tone, neutral tile) and generated Song Map covers. No stock photos or album art |

### Instrument drawings

Shipped as vector assets, one tone, so they tint per state.

| Drawing | Covers |
|---|---|
| strings | violin and string sections |
| flute | flute and bansuri |
| piano | piano and electric piano |
| guitar | |
| veena | sitar and plucked Indian instruments |
| tabla | Indian percussion |
| drums | |
| bass | |
| voice | |
| brass | |
| bells | mallets |
| synth | lead synths |
| pad | pads and choir |

Each library family maps to one drawing (`InstrumentFamily → drawing`).

### Song covers (owner, 6 Nov: D2 + D3)

1. **The song file's own embedded artwork** (ID3 APIC / MP4 `covr`), read on the iPhone, never downloaded.
2. Otherwise, **a generated cover** from the song's analysis:
   - **Mood sets the colours:** energy + major / minor → a three-colour gradient. For example, intense = deep red / amber, celebratory = teal / yellow, romantic = violet / peach.
   - **Sections set the shapes:** colour = repetition group; the hook is amber.
   - **Large covers (≥ 90 pt; Continue card, Analysing): style D2 "Ring over Aura".** The glowing waveform across the cover, with the Song Ring (sections as arcs, hook arc amber) as a record on top.
   - **Small covers (rows, the Play header): style D3 "Halo".** A soft radial waveform halo around a thin section ring.
   - **Drawing:** in a `Canvas`, cached as an image per song (re-drawn only when the analysis changes).

### Song Map

- **Data:** sections (width = length, height = energy) from the analysis.
- **Colour:** greys by repetition group; amber marks the current section; ★ marks the hook.
- **Drawing:** a `Canvas`, cached per song.
- **Sizes:** 48 pt row cover, 96 pt continue cover, full-width Play timeline.

## 1. Structure

```
Tab bar: Songs · Play · Record · Settings
Play (song open): nav bar (‹ Songs · song title · ⋯) → fixed page control → page content (scroll) → fixed transport → tab bar
Pages: Play (default) · Mix · Tone · Arpeggio · Sections        ids: page.play, page.mix, page.keyboard, page.arpeggio, page.sections
Sheets: Tone editor · Sound browser · Compare · Correct chord · Edit section · Import · Listen
```

## 2. Screens

### 2.1 First run (sheet, 2 steps)

| | |
|---|---|
| Purpose | Get to the first song fast |
| Step 1 "Welcome" | App mark; "Play film-song tones on your Casio." Primary **Connect your Casio** (→ connection guide); secondary "Later" |
| Step 2 "Ready" | Primary **Import a song** (→ Files); secondary "Explore first" |
| States | Casio already connected: step 1 shows ✓ "Casio connected" and Continue |
| ids | `setup.connect`, `setup.later`, `setup.import`, `setup.explore` |

### 2.2 Songs

| | |
|---|---|
| Purpose | Choose or add a song |
| Layout | Large title "Songs"; connection chip (amber "Casio not connected" / neutral "Casio connected", tap → guide); **Continue** card (96 pt Song Map cover, title, meta, tone drawings + name, 52 pt play button); **Import song** (primary) + Listen (secondary); search field; "Your songs" list (48 pt cover, title, film · language, status) |
| Row status | `Analysing 34%` (amber) · `Separating 42%` (amber) · `✓ Ready` (neutral) · `Needs attention` (red text + icon) |
| States | **Empty:** illustration + "Import a song you own" + primary Import. **No search results:** "No songs match" |
| Actions | Tap row → Play (Play page). Swipe row → Delete (a visible ⋯ menu offers the same) |
| ids | `songs.continue`, `songs.import`, `songs.listen`, `songs.search`, `songs.row.<title>` |

### 2.3 Analysing (Play page while running)

| | |
|---|---|
| Purpose | Show progress as results; allow playing early |
| Layout | Song Map cover filling in; step list: Beat → Key & chords → Sections → Separating parts (progress bar + time left) → Matching tones. Each step has an icon, a name and its result ("124 BPM · 4/4", "F♯ minor", "6 sections · hook found ★"), plus ✓ when done |
| Primary | **Play now** (enabled once the beat is found) |
| Errors | The failed step shows "Couldn't separate the parts" + **Try again**; the other results stay |
| ids | `analysis.step.<name>`, `analysis.playNow`, `analysis.retry`, `analysis.cancel` |

### 2.4 Play › Play (performance view, default)

| | |
|---|---|
| Purpose | Play along without navigating (iReal Pro + MainStage) |
| Layout (top → bottom) | "NOW" + section name (display, ★ if hook) · "NEXT" section + countdown · Song Map timeline (tap = jump, current section amber, playhead) · Chord card: chord now (display), the next 3 chords, **keys guide** (21-key Casio strip: left-hand keys amber, next melody note outlined) · Tone row (drawings + tone name, → Tone page) |
| Transport (fixed) | progress + times · Loop section · −5 s · Play / Pause · +5 s · Speed |
| States | No chords → the chord card is hidden. No melody → no melody key. No audio → caption "Play starts the song clock" |
| Performance | Section / chord / keys views observe `LiveState` only; fixed heights; cross-fade on section change |
| Taps | Chord card → Correct a chord (2.10). Section block → jump |
| ids | `play.section`, `play.map`, `play.chord`, `play.keys`, `play.tone`, `transport.*` |

### 2.5 Play › Mix

| | |
|---|---|
| Purpose | The backing band: choose what you play |
| Layout | "Parts" + Reset · rows per part: 44 pt instrument tile + 8 pt part-colour dot, name, one-line note ("Closest: Arabic Strings" / "Muted — you play it"), volume slider (visible), **Mute** and **Solo** buttons (labelled, 44 pt) · "Split Music into Lead & Backing" (secondary, when available) · "Original plays hard parts" toggle row (shows the chosen sections) |
| States | Not separated → empty state "Separate the parts to mix them" + primary **Separate**; separating → progress row |
| ids | `stem.header.<id>`, `stem.volume.<id>`, `stem.mute.<id>`, `stem.solo.<id>`, `parts.split`, `parts.hardParts` |

### 2.6 Play › Tone (signature screen)

| | |
|---|---|
| Purpose | Understand and keep or change the recommended sound |
| Layout | Suggestion card: "Suggested for the hook" chip + "In use" state; **one large instrument drawing** (secondary layer drawing overlaps small); tone name (title); character line ("Warm · expressive · all 61 keys"); **Why** sentence ("The song's hook — BGM, heard 3× — is played on strings."); buttons **Change** · **Compare** · Tone scope control (Whole song / Per section) · Layers list (drawing, name, level slider, ▶ hear) + "Edit" |
| Rules | No embedding scores or raw confidence. One plain sentence. "Both separations agree" appears in the Why sentence only when true |
| States | No suggestion yet → "Tone appears after analysis" with a step indicator. Per-section mode → section picker row above the card |
| ids | `tone.card`, `tone.change`, `tone.compare`, `tonemode.main`, `tonemode.sections`, `tone.layer.<n>`, `tone.editMain`, `tone.hookSource` |

### 2.7 Tone editor (sheet)

| | |
|---|---|
| Purpose | Adjust one layer (Logic Details pattern) |
| Layout | Layer header (84 pt drawing, name, source "Real instrument · VSCO"; **Audition**, Swap) · card: Level, Brightness, Reverb sliders + Mute / Solo · Details rows (icon + plain summary): Envelope "Slow attack", Filter & EQ "Fitted to the song", Vibrato & glide, Keys "All 61" → each opens its own screen · Add layer · Effects |
| ids | `tone.done`, `layer.header`, `layer.level`, `layer.brightness`, `layer.reverb`, `layer.details.<name>`, `layer.drive` (kept) |

### 2.8 Sound browser (sheet)

| | |
|---|---|
| Purpose | Find, hear and use a sound (GarageBand) |
| Layout | Search · "For <section>": 3 closest as 108 pt tiles with ▶ · family chips (All, Strings, Winds, Keys, Indian, Plucked, Synth) · 3-column grid of tiles (name + "Built-in" / "9.2 MB · Get" / "Installed") · fixed bottom bar: selected sound + **Use this** |
| Interactions | Tap tile = select + preview on the song's melody; Get downloads in place with a progress ring; Use this applies and closes |
| ids | `sounds.search`, `sounds.tile.<name>`, `sounds.get.<pack>`, `sounds.use` |

### 2.9 Compare (sheet)

As today (`BlindCompareView`), restyled with tokens: two sounds, Start blind test, X / Y play, choose.
ids: `compare.*` (existing).

### 2.10 Correct a chord (sheet)

| | |
|---|---|
| Purpose | Fix an AI chord in two taps (Chord Tracker) |
| Layout | "TonePilot heard **Em**. Pick the right chord:" · two big buttons (most likely / also possible) · "Something else": root row (C–B, 44 pt) + type segmented (Major, Minor, 7, m7, sus) · **Hear it** · **Fix all repeats** · Save |
| ids | `chord.option.<n>`, `chord.root.<n>`, `chord.type`, `chord.hear`, `chord.repeats`, `chord.save` |

### 2.11 Play › Arpeggio

| | |
|---|---|
| Purpose | Accompaniment that follows your left hand |
| Layout | Status line: **"Waiting for your chord" / "Playing the fill"** (clear state) · Live fill-in toggle · section chips · pattern name + "Learned from Pallavi" + Change · pattern grid (larger, 44 pt steps) · Preview (primary when not live) · Sound row · skipped sections ("No fill — block chords here" + Add a fill anyway) |
| ids | existing `arpeggio.*` |

### 2.12 Play › Sections

| | |
|---|---|
| Purpose | See how the sound changes through the song |
| Layout | Song Map (full width) · list: colour bar, section name (★ hook), time range, tone drawing + name, ⋯ (Edit timing, Change tone, Loop) · tap row = jump |
| ids | `sections.row.<n>`, `sections.more.<n>` |

### 2.13 Record

| | |
|---|---|
| Purpose | Capture a performance (Ableton Note) |
| Layout | Big record button + time · "Include the song parts" toggle · "Start on first key" toggle · Recordings list (name, length, share) |
| States | **Empty:** "No recordings yet · Saved as MP3 in Files" |
| ids | existing `record.*` |

### 2.14 Settings

| | |
|---|---|
| Layout | Casio card (status + Set up) · Keyboard & audio (Connection guide, Velocity, Diagnostics) · Sound (Sound library → browser, Sound engine) · Separation (Parts 4 / 6, Check with both models) · Storage & about (On this iPhone, Back up, Licences) |
| ids | existing `settings.*` plus `settings.casio`, `settings.library` |

## 3. Components and states

| Component | States |
|---|---|
| Primary button | normal · pressed · disabled · loading (spinner + label) |
| Segmented (pages) | selected · unselected · scrolls at accessibility sizes |
| Part row | playing · muted (dimmed, "Muted — you play it") · solo (others dimmed) · loading |
| Instrument tile | default · selected (amber outline) · auditioning (level ring) · not installed ("Get") · downloading (ring %) |
| Step row (analysis) | waiting · running (amber + progress) · done (✓ + result) · failed (red text + Try again) |
| Chip | neutral · attention (amber) · error (red, text + icon) |
| Song Map | static · live (playhead) · loop (looped section outlined) |
| Keys guide | idle (no chord) · chord lit · drone ("Sa–Pa drone" label) |

## 4. Journeys → screens (target taps, re-measured after the build)

| # | Task | Path | Target |
|---|---|---|---|
| 1 | Import | Songs › Import song › Files | 2 |
| 2 | Analyse | automatic (Analysing view) | 0 |
| 3 | Find the hook | Play › Tone (or ★ on the Play page) | 1 |
| 4 | Review the tone | Tone card | 1 |
| 5 | Preview an alternative | Tone › Change › tap tile | 2 |
| 6 | Edit a layer | Tone › Edit › layer | 2–3 |
| 7 | Back to playback | Done / Play page | 1 |
| 8 | Change section | tap the Song Map | 1 |
| 9 | Correct a chord | tap the chord › pick | 2 |
| 10 | Play | Songs › song › play | 2 |

## 5. Build order

1. **Play shell:** fixed pages, context, performance view, keys guide, Song Map timeline. *(The design-system foundation and shell are coded, not yet built.)*
2. **Tone page:** suggestion card + layer list, and the Sound browser sheet.
3. **Mix rows**, and correcting a chord from the chord card.
4. **Songs:** Continue card, Song Map covers, status, empty state; the Analysing view.
5. **Tone editor and Arpeggio** restyle; **Sections**.
6. **Settings** regroup; **first run**; **Record** restyle.
7. **Copy pass**, accessibility pass, after screenshots, journeys re-measured.

**Every step:**
- passes the full build (speed and crash gate, budgets, core tests);
- adds its identifiers to the tests;
- is compared against the v4 mockups.
