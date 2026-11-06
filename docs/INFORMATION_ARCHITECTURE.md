# TonePilot — Information architecture

*6 Nov 2026 · current structure from the code and screenshots; proposal follows the locked brief (three places; Play = central workspace + performance).*

## 1. Current IA

```
Tab bar
├── Songs ─ search · Import song · Listen · playlists · song rows → opens Play
├── Play (Song Studio)                     [one long scroll + fixed transport]
│   ├── Header (song, key, BPM, section) · analysis status · separation card · intro tip
│   ├── Timeline (waveform + section chips) · chord guide strip · "Your keys: Main tone / Per section"
│   ├── Page bar: Mix | My keys | Arpeggio | Sections        ← under the transport (UX_AUDIT C1)
│   ├── ⋯ menu: Analysis details & corrections · Melody & chord guide · Sound library (advanced)
│   │           · Re-analyse · All notes off · Close song
│   └── Sheets: Tone editor · Tone picker · Blind compare · Edit section · Listen
├── Record ─ record panel · recordings
└── Settings ─ keyboard & audio · sound engine · SoundFonts · sample instrument · separation models
              · check with both models · REAL INSTRUMENT SOUNDS (17 packs) · analysis server
              · your data · licences
```

## 2. Problems

1. **Sounds are spread over three places:**
   - sound packs (Settings);
   - SoundFonts and sample instrument (Settings);
   - the sound library / Tone Studio (Play ⋯ menu, labelled "advanced").
2. **Correction tools are hidden** in an overflow menu: analysis details and the chord guide.
3. **Inside Play, the shared context outweighs the pages.** Performance and configuration share one scroll.
4. **Record is a top-level tab**, but it's a performance action on the current song. It still earns a tab for lawful MP3 export of your own playing; this is kept (see §3), because removing a tab would make recordings harder to find.
5. **Settings mixes one-time setup, ongoing preferences, content (sound packs) and legal.**

## 3. Proposed IA

```
Tab bar (unchanged count; Play is the centre of gravity)
├── Songs ─ Import song (single entry) · Listen · search · song rows (status at a glance) → opens Play
├── Play — the song workspace
│   ├── Context strip (always visible, compact): song · current section → next section · tone name
│   ├── Segmented control (fixed, top): Play | Mix | Tone | Arpeggio | Sections
│   │   ├── Play — performance view: big section map, chords now/next, transport (calm, arm's length)
│   │   ├── Mix — parts: mute / solo / volume; split Music; "Original plays the difficult parts"
│   │   ├── Tone — suggestion card (hook + recommended tone + why) [Use · Change · Compare]
│   │   │          → Tone editor sheet (layer tiles → Details)
│   │   ├── Arpeggio — live fill, style, preview, skipped sections
│   │   └── Sections — list with per-section tone; tap = jump; ⋯ = timing / tone
│   ├── Chords: tap the chord strip → correct (pick from top-2, then root / type)   [was ⋯ menu]
│   ├── Sound browser sheet (one place): Suggested · Built-in · Real instruments (packs) · My samples
│   │      filters by family · tap = audition · packs show size + Get
│   └── ⋯ menu: Analysis details · Re-analyse · All notes off · Close song
├── Record ─ unchanged structure; copy shortened
└── Settings ─ Keyboard & audio · Sound engine · Separation · Storage & data · About
               (sound packs → Sound browser; packs storage stays listed under Storage)
```

### Why each move helps

| Move | Usability benefit |
|---|---|
| Fixed segmented control at the top of Play | Every page is one tap away and visible (fixes C1); the user always knows which mode they're in |
| New **Play** page (performance view) as default | Performance separated from configuration (principle 4); usable at arm's length (MainStage pattern) |
| Context strip replaces repeated header / timeline / guide | Musical context always visible in one line (principle 5); page content starts above the fold (fixes C2) |
| **Tone** page leads with a suggestion card | Hook and tone appear as suggestions with Use / Change (principle 2, brief "suggest then refine") |
| One **Sound browser** | One place to find, audition and download sounds (Logic / GarageBand pattern); Settings gets shorter |
| Chord strip tappable | Correction in context instead of a hidden menu (Chord Tracker pattern) |
| Settings regrouped | Setup, preferences, storage and legal no longer interleave |

### Kept as is

- **Three primary places plus Record.** The brief's "three places" are Songs / Play / Settings. Record stays a tab because its recordings list is a destination people return to, not a mode. It moves into Play only if the owner decides so.
- **Section chips:** one-tap section jump.

## 4. Navigation map (proposed)

```
Songs ──tap song──▶ Play[Play page] ◀──tab── (any)
   │                  ├─Mix ├─Tone ──Edit──▶ Tone editor (sheet) ──layer──▶ Details
   │                  │      └─Change──▶ Sound browser (sheet) ──Get──▶ pack download
   │                  ├─Arpeggio ├─Sections ──⋯──▶ Edit section (sheet)
   │                  └─chord strip──▶ Chord correction (sheet)
   └─Import song──▶ Files ──▶ (analysis runs) ──▶ Play
Settings ──▶ Keyboard & audio · Sound engine · Separation · Storage & data · About ▶ Licences
```

## 5. Interaction flows

See `USER_JOURNEYS.md` (10 validation tasks, current vs proposed step counts).
