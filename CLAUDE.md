# TonePilot — working rules

## Every feature: smooth, fast, no crashes (the owner's standing requirement)

A change is not done until all of these hold:

1. **Speed & crash gate passes** (`.github/workflows/ios-build.yml`, step "Speed & crash tests"):
   the app is driven through every tab and Song Studio page on an iPhone simulator
   (`App/UITests/TonePilotUITests.swift`, demo song from `App/Sources/Services/UITestSeed.swift`).
   A crash, a freeze (a screen not responding within its limit), launch > 4 s or peak memory
   > 1.5 GB fails the build, and nothing is published.
2. **Speed budgets pass** (`Packages/TonePilotCore/Tests/TonePilotCoreTests/SpeedBudgetTests.swift`,
   run in release): engine < 25% of real time, pattern learning < 20 s per 4-minute song,
   analysis < 20 s per 2-minute song. Add a budget for any new heavy work.
3. **New screens and controls are added to the stress test**, with accessibility identifiers.
4. **Smoothness rules for UI code:**
   - High-frequency values (song position, meters) live in `LiveState`; only small views observe it.
   - No layout that changes size while playing (fixed frames, `opacity` instead of `if`).
   - Heavy work (decoding, analysis, separation, pattern learning) never on the main thread;
     separation runs at `.userInitiated` with memory-based worker counts.
   - Gestures must not cover sliders or scroll views (put tap/long-press on a header area).
5. Core tests pass (`swift test`, Linux via Docker `swift:6.0-noble` or macOS).

Report the measured numbers (the "App speed" and "Speed budget" annotations) with each build.

## Quality
- Separation quality must never go below the current engine: `coreml-convert.yml` checks the
  app's separator against PyTorch Demucs per part before the model is published.

## Constraints
- Don't analyse ripped/pirated MP3s; don't download from YouTube or piracy sites.
- Don't recommend free-signing / enterprise-certificate install services.
