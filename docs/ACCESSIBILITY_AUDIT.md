# TonePilot — Accessibility audit (before)

*6 Nov 2026 · default and largest accessibility text size (`UICTContentSizeCategoryAccessibilityL`) screenshots (`docs/ux-screens/before/B*`), plus a code scan. VoiceOver wasn't run interactively: the simulator in CI has no audio or VoiceOver output. The findings below come from code and layout, and a VoiceOver pass is listed as a remaining check.*

| # | Area | Finding | Severity | Evidence |
|---|---|---|---|---|
| A1 | Dynamic Type | Text scales (system text styles are used), but layouts don't adapt: the volume value wraps to "9 / 0", "sec-tion" hyphenates, "Blind comparis…" truncates, part names truncate to "Music…", "Chang / e" | High | B21b, B22, B23b, B31 |
| A2 | Dynamic Type | The page bar and transport plus the tab bar take ~45% of the screen at large sizes; content area very small | High | B21–B24 |
| A3 | Touch targets | M / S buttons in the tone editor and the ⋯ section menu buttons look < 44 pt; page-bar icons are partly covered by the transport (C1) | High | B30b, B24b, A21 |
| A4 | Colour | Status uses colour alone in places: part cards' coloured borders; the red "No keyboard" dot (has text, good); stem colours carry no text meaning | Medium | A21b, A10 |
| A5 | Contrast | Secondary text at caption size on `Color(white: 0.11)` panels is borderline (estimated, not measured); amber-on-amber chips ("Download") have low contrast | Medium | A51–A54 |
| A6 | VoiceOver labels | Icon-only buttons mostly have labels (transport, ⋯ "More", Dismiss). Missing or weak: page-bar icons at default size (no visible text), part-card sliders (label = part name?), section chip timing | Medium | code |
| A7 | Reduce Motion | No custom animations found that ignore it (system transitions only) | Low | code |
| A8 | Light / dark | Dark only (forced). Acceptable for a performance app, but "Increase Contrast" isn't handled by the custom colours | Medium | `TonePilotApp.swift`, `Theme` |
| A9 | Identifiers | Many screens have no identifiers (`ListenModeView`, `SectionEditorSheet`, `SongDetailView`, `MelodyChordGuideView`, `ToneSelectorView`…), so they can't be stress-tested or audited automatically | Medium | code scan |

## Planned fixes (design system + implementation)

- **Dynamic Type:**
  - text styles only;
  - `ViewThatFits` / vertical stacks at accessibility sizes for part cards and the tone switch;
  - numbers with `.monospacedDigit()` and `minimumScaleFactor` only for numeric readouts.
- **Touch targets:** a 44 pt minimum enforced in shared button / icon-button components.
- **Colour:**
  - semantic tokens with Increase-Contrast variants;
  - status always paired with an icon and text;
  - stem colour as a small marker, not a whole tinted card.
- **VoiceOver:**
  - labels, values and hints on custom controls (sliders announce "Vocals volume, 90 percent");
  - grouped cards (`.accessibilityElement(children: .combine)`) where it reads better.
- **Identifiers:** every interactive control in redesigned screens gets one, and the screen tour covers every screen.
- **Remaining manual checks:** an interactive VoiceOver pass and a contrast measurement on device. These are listed in the roadmap, not claimed done.

## Contrast check of the tokens (6 Nov, after the build)

| Text colour | on canvas | on surface | on elevated |
|---|---|---|---|
| textPrimary #F5F5F7 | 17.3 | 15.3 | 12.8 |
| textSecondary #A3A3AB | 7.5 | 6.6 | 5.6 |
| accent #FFAD32 | 10.1 | 8.9 | 7.5 |
| textTertiary #707078 | 3.8 | 3.4 | **2.8** |

onAccent on accent: 10.1. `textTertiary` is below 4.5 : 1 for text and below 3 : 1 on `elevated`,
so it is kept for placeholders and decorative icons only. Fixed: the Analysing "Waiting" step, the
Arpeggio grid's rest dots and the first-run step counter now use `textSecondary`.
