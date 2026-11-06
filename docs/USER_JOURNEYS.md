# TonePilot — User journeys (10 validation tasks)

*6 Nov 2026.*
- **Current** steps are counted from the code and the before screenshots: taps, plus scrolls ("S") needed at default text size on an iPhone 16-size simulator.
- **Proposed** steps are the target for the redesign. They are re-measured after implementation using the screen tour; the after column will be filled from screenshots, not estimated.

| # | Task | Current path | Current | Proposed path | Target |
|---|---|---|---|---|---|
| 1 | Import a song | Songs › Import song › Add song sheet › Files › pick | 3 taps + Files | Songs › Import song › Files › pick (no intermediate sheet when nothing needs choosing) | 2 taps + Files |
| 2 | Analyse it | Automatic after import; progress in Play (status card) and the song row | 0 | Same; one progress line in the context strip, plain step names | 0 |
| 3 | Find the main hook | Play › scroll to page bar (S) › My keys (hard to hit, UX_AUDIT C1) › scroll (S) › read "From Chorus — the song's hook" (only in Main-tone mode) | 2 taps + 2 S | Play › **Tone** (top segmented control): suggestion card names the hook first | 1 tap |
| 4 | Review the tone recommendation | as 3, then Edit main tone › "Why the AI built this" (truncated) | 3 taps + 2 S | Tone: card shows tone, hook and a one-line reason, with Use / Change / Compare | 1 tap |
| 5 | Preview an alternative sound | Edit main tone › scroll (S) › layer › change sound › picker; no audition list in the card | 5 taps + 2 S | Tone › Change › Sound browser: Suggested list, tap = audition | 2 taps |
| 6 | Edit a layer | My keys › Edit main tone › scroll (S) › expand layer › Effects & EQ › scroll (S) › control | 5 taps + 3 S | Tone › Edit › layer tile (sound, level, brightness on the tile) › Details for the rest | 2–3 taps |
| 7 | Return to playback | Done (transport always visible) | 1 | Done; or the **Play** segment | 1 |
| 8 | Move between sections | Tap a section chip | 1 | Same (section map on the Play page, chips in the context strip) | 1 |
| 9 | Correct a chord | ⋯ › Melody & chord guide › find chord › menu › pick | 4–5 taps | Tap the chord strip › pick from top-2 (or root / type) | 2 taps |
| 10 | Play the song | Songs › tap song › play | 2 | Same, landing on the Play page (performance view) | 2 |

**Totals (tasks 1–10):**
- current ≈ 25 taps + 9 scrolls;
- target ≈ 14 taps + 0 scrolls.

## Journey notes

### First-time experience

- **Current:** Welcome → Install sounds (nothing to do) → Connect keyboard (cables, audition) → Songs, with no hint of the next step.
- **Proposed:**
  1. **Welcome:** one sentence, plus "Connect your Casio" (with "Later").
  2. **Ready:** "Import a song you own", the primary button, lands on Songs with the import sheet open.

  The cable guide stays in Settings › Keyboard & audio.

### Song import and analysis

Progress is one line with plain step names ("Finding the beat…", "Separating parts… 40%", "Matching tones…"). Each finished step appears in place: chords, sections and tone. Problems show as one actionable line, not a paragraph.

### Song Studio (Play)

- The context strip is always visible.
- The segmented control is fixed at the top.
- The Play page is the default and is calm while playing.
- Configuration lives in Mix / Tone / Arpeggio / Sections.

### Tone Maker

The suggestion card comes first: hook → tone → why. Then:
- **Use:** on by default.
- **Change:** opens the Sound browser.
- **Compare:** blind A/B.
- **Edit:** layer tiles, then Details.

### Sound library

- One browser, organised as Suggested / Built-in / Real instruments / My samples.
- Family filter chips.
- Tap to audition.
- Packs show size and Get.

### Playback and MIDI

- Large transport.
- Connection status is a quiet chip, amber when the keyboard is missing (not red); tapping it opens the guide.
