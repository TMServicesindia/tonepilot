# TonePilot design system

*v1 · 6 Nov 2026*

- **Source of truth:** `design/tokens/tonepilot.tokens.json`. It's platform-neutral, so a Compose theme can be generated from it.
- **SwiftUI implementation:** `App/Sources/DesignSystem/` (`Tokens.swift` and `Components.swift`).
- **CI check:** `.github/scripts/check_tokens.py` fails the build if the Swift tokens drift from the JSON.

## Principles

1. **A calm instrument companion.** Quiet surfaces and one warm accent; legible at arm's length.
2. **Colour carries meaning.**
   - Amber means *act here or selected*.
   - Section colours identify repeats.
   - Part colours are small markers.
   - Status colours always come with text and an icon.
3. **Native first.**
   - System text styles (Dynamic Type), SF Symbols, native sheets and navigation.
   - Tokens are portable; interactions are never compromised for portability.
4. **Group only when it helps.**
   - Surfaces separate by colour, not shadow.
   - No card inside a card.
   - No decorative gradients.
5. **One obvious next action.** A screen or card has at most one primary (filled) button.

## Tokens

### Colour (semantic roles)

| Token | Dark | Light | Use |
|---|---|---|---|
| `canvas` | #0B0B0D | #F4F4F6 | Screen background |
| `surface` | #151518 | #FFFFFF | Grouped content |
| `elevated` | #202024 | #ECECF0 | Chips, segmented track, inputs |
| `border` / `divider` | #2C2C32 / #242429 | #D9D9DF / #E3E3E8 | Hairlines (high contrast: #4A4A52) |
| `textPrimary` | #F5F5F7 | #111114 | Titles, body |
| `textSecondary` | #A3A3AB | #5C5C66 | Metadata (high contrast: #C9C9D0) |
| `textTertiary` | #707078 | #8C8C96 | Placeholders, disabled |
| `accent` / `onAccent` | #FA9E33 / #121212 | #D9770A / #FFFFFF | Primary action, selection, playhead |
| `accentMuted` | accent 16% | | Selected and suggestion backgrounds |
| `success` / `warning` / `error` / `info` | #3DD27A / #FFD24D / #FF5A4F / #6CC8FF | | Status (always with text) |
| `section[8]` | amber, teal, violet, pink, yellow, green, indigo, cyan | | Section by repetition group |
| `part.*` | vocals pink, drums amber, bass violet, music teal… | | Marker per separated part |

The app currently runs dark only. Light values are defined and ready, and switching is a later product decision.

### Spacing (4-point grid)

| Token | Value |
|---|---|
| `xxs` | 2 |
| `xs` | 4 |
| `s` | 8 |
| `m` | 12 |
| `l` | 16 |
| `xl` | 24 |
| `xxl` | 32 |

Semantic aliases: `screenMargin` 16, `sectionGap` 24, `componentPadding` 16, `inline` 8.

### Radius and sizes

- **Radius:** `s` 8, `m` 12, `l` 16, `full` capsule.
- **Sizes:**
  - `touchTarget` 44 (HIG minimum);
  - `primaryButton` 50;
  - `transportPlay` 64;
  - `segmentedHeight` 40;
  - `artwork` 44.

### Typography (roles → text styles)

| Role | iOS | Android |
|---|---|---|
| largeTitle | largeTitle bold | headlineLarge |
| screenTitle | title2 bold | headlineSmall |
| section | headline | titleMedium |
| subsection / label | subheadline semibold | titleSmall / labelLarge |
| body | body | bodyLarge |
| bodySecondary | subheadline | bodyMedium |
| caption | footnote | bodySmall |
| metadata | caption | labelSmall |
| button | headline | labelLarge |
| numeric | monospaced digits | tabular nums |
| display | title, rounded, bold (performance readouts) | displaySmall |

### Elevation and motion

- **Elevation:** none on content. The floating transport uses a material.
- **Motion:**
  - `quick` 0.15 s, `standard` 0.25 s;
  - Reduce Motion means no animation (`DS.Motion.standard(reduceMotion:)`);
  - nothing animates in response to the song position.

## Components (SwiftUI)

| Component | Purpose | Notes |
|---|---|---|
| `.dsSurface()` / `.dsCanvas()` | Group content; screen background | Radius `l`, padding 16 |
| `DSSectionHeader` | Heading with an optional action ("Edit") | Header trait; action ≥ 44 pt |
| `.dsPrimary` / `.dsSecondary` button styles | One filled primary; neutral secondary | 50 pt tall, full width, disabled state |
| `DSChip` | Status / metadata | Text always present; neutral, accent, success, warning, error |
| `DSSegmentedControl` | Song Studio pages | Fixed at the top; equal widths, or scrolls at large text (no truncation); selected trait; ids `page.<raw>` |
| `DSNavigationRow` | Tappable summary row (e.g. Tone on the Play page) | Combined accessibility element |
| `DSEmptyState` | Empty / not-yet states | One line plus at most one action |
| `StudioContextBar` | Song, key and tempo, always visible in Play | `studio.context` |
| `PerformanceHeader` | Current section (large) and next section with countdown | Observes `LiveState` only here; fixed lines so nothing moves while playing; `play.section` |

**Still in existing code, being migrated:**
- `Theme.*` (now mapped onto `DS.Palette`);
- `Card` (title + surface);
- `StatusPill`, `ConfidenceBadge`;
- `TransportBar`, `SectionTimeline`.

## Rules for screens

- **No raw styling:** no raw colours, font sizes, spacing or radii. Use `DS.*`. Only 0 is allowed inline.
- **Identifiers:** every interactive control gets an accessibility identifier, and new controls join the speed-and-crash test.
- **Copy:** text follows `docs/UX_COPY_AUDIT.md`. Labels are verbs; one idea per sentence; details go in info sheets.
- **Performance:** high-frequency values only in small views observing `LiveState`, with fixed frames (CLAUDE.md smoothness rules).
