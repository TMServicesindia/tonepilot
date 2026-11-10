# UX implementation roadmap

*6 Nov 2026 · build contract: `TONEPILOT_SCREEN_SPEC.md` · visual reference: `design/mockups/v9` (+ D2/D3 covers)*

The owner's brief: a calm instrument companion, not a miniature DAW. Each step below goes through
the full build (`ios-build.yml`: speed & crash gate, budgets, core tests) and a `ui-screens.yml` run.

## Status by step

| Step | Screens | State | Notes |
|---|---|---|---|
| 1 | Play shell: fixed pages, performance view (NOW / NEXT), Song Map timeline, chord + keys guide, tone row | Built | ids `play.section/map/chord/tone`, `page.*` |
| 2 | Tone page: suggestion card, layer levels, hook source, fusion line | Built | ids `tone.*`, `tone.layer.level.<n>` |
| 3 | Mix part rows (visible Mute / Solo / volume) · Correct a chord sheet | Built | ids `stem.*`, `chord.*` |
| 4 | Songs: Continue card, D2/D3 covers (embedded artwork first), status chips, empty state, amber "Casio not connected" chip, ⋯ menu · **Analysing** step list | Built | ids `songs.*`, `analysis.*`, `connection.status`; `-TPAnalysing` seed |
| 5 | Tone editor (header + Level / Brightness / Reverb + Details rows) · Arpeggio (state line, larger grid) · Sections (Song Map + rows) · AI parts row · **Sound browser** | Built | ids `layer.*`, `arpeggio.state`, `sections.row/more.<n>`, `sounds.*` |
| 6 | Settings (Casio card + four groups, coloured icon squares) · First run (2 steps) · Record | Built | ids `settings.casio`, `settings.licences`, `setup.*`, `record.empty` |
| 7 | Copy pass · accessibility pass · after screenshots · journeys re-measured | Built | Automated audit 240 → 224 issues; journeys in `USER_JOURNEYS.md` |

Steps 1–6 shipped in **v0.3.101** (6 Nov); step 7 in **v0.3.111** (10 Nov). Both full builds green.

## Deviations from the spec (and why)

- **Analysing:** the analyser returns every result at the end, so a step shows ✓ *Done* rather than
  its result; results appear on the Play page. Separation keeps its own card (it runs after the first
  analysis). *Play now* is secondary because the transport play is the screen's primary.
- **Sound browser:** "For <section>" shows **From this song** (the song's own tones) rather than
  "3 closest", because no per-section ranking is stored for the browser. Sound packs are still
  downloaded in Settings › Real instrument sounds (no "Get" on tiles yet).
- **Tone editor details** open in place (disclosure rows) instead of each pushing a screen: fewer
  taps, and the sheet keeps its Done button in view.
- **Record:** the record button stays red, the one non-error use of the error colour (universal
  record convention, HIG).

## Still to do

1. **Copy pass** against `UX_COPY_AUDIT.md` on the screens not rebuilt: `SongDetailView`,
   `MelodyChordGuideView`, `SectionGuideView`, `ListenModeView`, `ToneSelectorView` (they remain
   reachable from secondary paths).
2. **Accessibility pass** (`ios-accessibility-audit`): VoiceOver order on Play, Dynamic Type at AX5
   on the Sound browser and Settings, contrast of `textTertiary` on `elevated`.
3. **After screenshots** for steps 5–6 (`ui-screens.yml`, label `after-6`) and a before/after sheet.
4. **Journeys re-measured** (spec §4) and written into `USER_JOURNEYS.md`.
5. Sound browser: tile "Get" for sound packs with a progress ring; per-section "closest" row once the
   matcher stores a ranking.
6. Remaining raw styling in legacy views (counted per file by the check in this doc's history).

## Platform-neutral design

Tokens live in `design/tokens/tonepilot.tokens.json`; `check_tokens.py` keeps the Swift tokens in
step. An Android Compose theme can be generated from the same file. No Android build is planned now.
