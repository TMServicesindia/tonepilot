# TonePilot — UX / UI audit (before)

*6 Nov 2026 · from simulator screenshots (`docs/ux-screens/before/`, run 42161012216, iPhone simulator, demo song) and the SwiftUI code. Judged against the locked brief in `docs/UX_COMPETITIVE_RESEARCH.md`.*

**Severity:**
- **Critical:** blocks or seriously confuses a primary task.
- **High:** substantial friction.
- **Medium:** inconsistency or extra effort.
- **Low:** visual refinement.

## 1. Screen inventory

| Area | Screen / sheet | File | Reached from | Shots |
|---|---|---|---|---|
| First run | Setup wizard (Welcome → Install sounds → Connect keyboard) | `SettingsView.swift` `SetupWizardView` | first launch | C00–C03 |
| Songs | Song list, search, Import / Listen, playlists | `LibraryView.swift` | tab | A10, B10 |
| Songs | Add song (file import) | `LibraryView.swift` `ImportSongView` | Import song | — |
| Songs | Listen Mode (microphone) | `ListenModeView.swift` | Listen | — |
| Play | Song Studio: header, timeline, chord guide, tone mode, page bar, transport | `SongStudioView.swift` | tab / open song | A21–A24, B21–B24 |
| Play › Mix | Song parts (mute/solo/volume), split Music, "Original plays the difficult parts" | `SongStudioView.swift` | page | A21b |
| Play › My keys | Tone name, hook source, feel, fusion line, Edit / Compare | `SongStudioView.swift` `MyKeyboardCard` | page | B22b |
| Play › Arpeggio | Live fill-in, sections, style, pattern grid, preview, sound, skipped sections | `SongArpeggioView.swift` | page | B23, B23b |
| Play › Sections | Sections & tones list (per-section tone, ⋯ menu) | `SongStudioView.swift` `StudioSectionsCard` | page | B24, B24b |
| Play (no song) | Free play | `SongStudioView.swift` `FreePlayView` | tab, no song open | — |
| Sheet | Tone editor (Main tone): rationale, master, keyboard map, layers, effects | `ToneStudioView.swift` `ArrangementEditorView` | Edit main tone / Edit sound | B30, B30b |
| Sheet | Tone picker (per section) | `SongStudioView.swift` `TonePickerSheet` | Change sound | — |
| Sheet | Blind comparison | `BlindCompareView.swift` | Compare blind | B31 |
| Sheet | Edit section (timing) | `SectionEditorSheet.swift` | section ⋯ | — |
| Pushed | Analysis details & corrections | `SongDetailView.swift` | Studio ⋯ menu | — |
| Pushed | Melody & chord guide | `MelodyChordGuideView.swift` | Studio ⋯ menu | — |
| Pushed | Section guide | `SectionGuideView.swift` | Sections | — |
| Pushed | Sound library (advanced) = Tone Studio, tone selector | `ToneStudioView.swift`, `ToneSelectorView.swift` | Studio ⋯ menu | — |
| Record | Record panel + recordings | `RecordView.swift` | tab | A40, B40 |
| Settings | Keyboard & audio, Sounds, Separation models, Real instrument sounds (17 packs), Analysis server, Your data, About | `SettingsView.swift` | tab | A50–A54 |
| Settings › | MIDI diagnostics, Casio setup, Troubleshooting, SoundFonts, Sample instrument, Analysis server, Licences | `SettingsView.swift`, `SamplePatchCreatorView.swift` | rows | — |
| **Dead code** | `AnalyseHomeView`, `PatchPicker` (never shown) | `AnalyseHomeView.swift`, `ToneStudioView.swift` | — | — |

## 2. Findings

### Critical

| # | Problem | Evidence | Why it matters |
|---|---|---|---|
| C1 | **The page switcher (Mix / My keys / Arpeggio / Sections) sits under the fixed transport.** At default text size only its top edge shows; the screen tour's taps on it landed on the transport, so pages never changed (A22–A24 all show Mix) | A21, A22, A23, A24: icon row clipped above the scrubber; `SongStudioView.swift` body: `StudioPageBar` comes after header, timeline, chord guide and tone switch inside the scroll view | The four main areas of the central workspace are hard to see and hard to hit. The user's main navigation inside Play is effectively hidden |
| C2 | **Every Play page repeats ~60% of a screen of shared content before its own content** (header, waveform, chord guide, tone-mode switch) | A21–A24 are identical above the fold; page content needs a scroll on every page | Violates "one obvious next action" and "preserve musical context": the user must scroll to reach anything they came for, while playing |

### High

| # | Problem | Evidence |
|---|---|---|
| H1 | **Performance and configuration are mixed** in one scroll: mixer sliders, split buttons, explanations, tone editing entry and analysis status all live in the same column as the transport (brief principle 4) | A21b, B22b |
| H2 | **Sound packs are 17 "Download" rows inside Settings**, without preview; the sound library lives elsewhere ("Sound library (advanced)" in the ⋯ menu). There are three separate places for sounds | A51–A54; `SettingsView.swift` `SoundPacksSection`; Studio ⋯ menu |
| H3 | **Chord correction is hidden** in the ⋯ menu ("Melody & chord guide"); the chord strip on Play isn't tappable | `SongStudioView.swift` toolbar |
| H4 | **The hook / tone recommendation isn't presented as a suggestion with accept / change.** It's a small menu label ("From Chorus — the song's hook") under the tone name, visible only in Main-tone mode | B22b; `MyKeyboardCard` |
| H5 | **The tone editor opens on technical controls** (rationale text, Master, CLIP meter, keyboard map) before the layers; layer rows use letters M / S and a "SoundFont" badge | B30, B30b |
| H6 | **Empty states take full cards:** "Right hand — No melody estimate for this song" occupies a large card on every page | A21–A24 |
| H7 | **The first run has an empty step** ("Install sounds — Default SoundFont installed") and ends without guiding to the one thing that matters: import a song | C01, C03 |

### Medium

| # | Problem | Evidence |
|---|---|---|
| M1 | Long helper paragraphs: "Separates the interlude melodies…", "Can't play a passage yet?…", "Records TonePilot's own sound straight from the app…", "After a song is separated, it is separated again…", the Settings footers | A21b, A40, A51, A53 |
| M2 | Truncation at default size: "Music & instru…", "Drums & percu…", "Sounds like Piccolo · 7…"; at large text: "Blind comparis…", "sec-tion", the volume value wrapping to "9 / 0", "Chang / e" | A21b, B21b, B22, B23b, B31 |
| M3 | Unclear control label: "Your keys · Main tone / Per section" | A21 |
| M4 | Colour noise: four saturated stem colours with tinted card backgrounds and coloured borders, an amber accent, amber glows behind the navigation and transport bars, a red "No keyboard" chip that reads as an error | A21b, A50, A10 |
| M5 | Duplicate entry points: "+" in the Songs toolbar *and* an "Import song" button; "Library" back button in Play *and* the Songs tab | A10, A21 |
| M6 | Inconsistent spacing and radii: 12 spacing values (incl. off-grid 3 / 6 / 10 / 14), 43 raw corner radii, 13 raw colours / font sizes; no shared tokens beyond 6 `Theme` colours | code scan |
| M7 | Settings mixes setup, sound engine, models, packs, data and legal in one long list (5 screens of scrolling) | A50–A54 |
| M8 | Dark mode is forced (`.preferredColorScheme(.dark)`); there's no light appearance | `TonePilotApp.swift` |

### Low

| # | Problem | Evidence |
|---|---|---|
| L1 | Section chips show start times ("0:09") that add little at a glance | A21 |
| L2 | The "1×" speed control has no label | transport |
| L3 | Primary buttons are small capsules on first run (Next / Start) | C00–C02 |

## 3. What already works (keep)

- **Transport:** fixed, with a large amber play button (Moises-like); time readout.
- **Songs:** clear primary action (Import song); song rows show status ("Parts ready").
- **Section chips:** on the timeline, one tap jumps to a section (validation task 8: 1 tap).
- **Mixer:** parts with mute / solo / volume are recognisable.
- **Tab bar:** four tabs with SF Symbols; amber identity.
- **Accessibility identifiers:** cover the stress-tested controls.

## 4. Priorities (fed into the roadmap)

1. **Play layout:** the page switcher becomes a fixed segmented control at the top of the workspace, shared context shrinks to one compact strip, and each page starts with its own content (C1, C2, H1).
2. **Suggest → accept / change** for hook, tone and chords (H3, H4).
3. **One Sound browser** (built-in, sound packs, samples) with audition, size and preview, leaving Settings (H2, M7).
4. **Design-system tokens + components** (M4, M6).
5. **Tone editor:** layer tiles first, technical controls under Details (H5).
6. **Copy reduction and empty states** (H6, M1, M2, M3).
7. **First run:** a 2-step welcome that ends on "Import a song" (H7).
