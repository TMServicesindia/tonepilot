# TonePilot — Phase 3 (Harmony) Report

**Date:** 1 November 2026 (IST) · **Owner instruction:** "Re-run the build later and start Phase 3."
**Status:** steps 1–3 are done (benchmark, hypothesis analyzer, held-out fixes + stem mode + held-out 3); see §6 for step 3. The new analyzer is better
than the current one everywhere it was measured, but it **does not yet meet every target** on the
untouched held-out set. Not wired into the app: **no user-visible change**.

## 1. What was built

- **Harmony benchmark** (`Benchmarks/HarmonyBenchmarks.swift`, opt-in, nightly in `bench.yml`).
  - Songs rendered from GeneralUser GS with a known chord on every beat.
  - Cases: triads; minor keys (one with a melody); sevenths; inversions (bass ≠ root); pedal bass;
    half-bar changes; drone (Sa–Pa + melody).
  - Three sets: in-sample (100 BPM), held-out 1 (128 BPM, other instruments) and held-out 2
    (84 BPM, other instruments; **never looked at while tuning**).
- **`HarmonyHypotheses`** (`Sources/TonePilotCore/Harmony/HarmonyHypotheses.swift`), plan item C3:
  - **Notes per beat:** non-negative least squares on a log-frequency spectrum, with every note
    modelled with its harmonics. Overtones are explained by the note that makes them.
  - **Bass is evidence:** the strongest low note is a root bonus; a chord tone gets a smaller bonus;
    a foreign note a small penalty. So inversions and pedal bass work.
  - **Chords:** 24 major/minor triads matched on the upper notes; a seventh is allowed without
    penalty; the third must sound. A small bonus for chords in the two best-fitting keys (major and
    minor readings, harmonic-minor V).
  - **Melody:** a top voice well above at least two accompaniment notes counts only weakly.
  - **Drone:** Sa and Pa steady over 8 units with no steady third → `drone:<Sa>`, never a triad.
    The tonic is the root of the fifth chain.
  - **Changes on any beat:** light smoothing; tracked beats longer than 0.6 s are analysed in halves,
    so half-tempo tracking does not hide half-bar changes.
  - **Alternatives:** up to 3 ranked alternatives per span.
- **Unit tests:** `HarmonyHypothesesTests` covers major/minor and changes on any beat, bass as
  evidence, drone, alternatives and speed.

## 2. Results (beat level; root + major/minor)

| Measure (target) | Set | Current analyzer | **Hypotheses** |
|---|---|---|---|
| Beat accuracy (≥ 85%) | in-sample | 73% | **90%** |
| | held-out 1 | 59% | **89%** |
| | held-out 2 (untouched) | 66% | **82%** ✗ |
| Minor keys (≥ 75%) | in-sample | 50% | **84%** |
| | held-out 1 | 55% | **85%** |
| | held-out 2 | 50% | **70%** ✗ |
| Half-bar changes | all three sets | 23–30% | **100%** |
| Drone labelled drone (≥ 90%) | in-sample / held-out 1 | 0% / 0% | **100% / 90%** |
| | held-out 2 | 0% | **31%** ✗ |
| Truth in alternatives (≥ 95%) | in-sample / held-out 1 | 82% / 76% | **98% / 98%** |
| | held-out 2 | 77% | **92%** ✗ |

**Speed:** 1.37 s per 4-minute song (Linux release). Budget: < 10 s, enforced in the unit test.

**Honesty notes:**
1. Several rules were adjusted while looking at the in-sample set, and two fixes came from held-out 1:
   - window placement (a real bug: windows reached into the previous beat);
   - drone tonic (an overtone made Pa–(its fifth) look like Sa–Pa).

   Only held-out 2 is a clean test, and on it the targets are not met.
2. **One benchmark flaw was corrected:** the melody used a C-major scale over C-minor chords. It now
   follows each case's key.
3. Everything is synthetic. Acceptance needs real audio (S4/S6), and there are 0 clips.

## 3. Gate status

| Phase 3 gate | Status |
|---|---|
| Chord targets on S1 | Met in-sample and on held-out 1; **not met on held-out 2** (82% / 70% / 31% / 92%) |
| Improvement on S4/S6 (real) | **Cannot run: 0 clips** |
| Drone passages never forced to a triad | Unit test passes; held-out 2 drone 31% → **not yet** |
| Both platforms | Android deferred |
| BTC comparison | Not started; BTC is only considered if it beats the improved DSP on real audio |

**Decision under your rules:** the hypothesis analyzer is **not switched on**. It is clearly better than
the current analyzer, but the targets are not all met and real-audio acceptance cannot run yet.

## 4. Files changed in Phase 3

- `Packages/TonePilotCore/Sources/TonePilotCore/Harmony/HarmonyHypotheses.swift` (new)
- `Packages/TonePilotCore/Tests/TonePilotCoreTests/HarmonyHypothesesTests.swift` (new)
- `Packages/TonePilotCore/Tests/TonePilotCoreTests/Benchmarks/HarmonyBenchmarks.swift` (new)
- `.github/workflows/bench.yml` (harmony benchmark in the nightly reproducibility run)

## 5. Next steps (waiting for your go-ahead)

1. Look at held-out 2's failures (drone with choir/steel guitar, minor keys at 84 BPM). Then make a
   **held-out 3**, so there is still an untouched set after that.
2. Run on harmony from the accompaniment stem (the app already separates parts), which removes most
   melody interference.
3. Your Indian recordings, for real-audio acceptance.

## 6. Step 3 (owner: "Go ahead with the next step")

**Fixes kept** (general causes found on held-out 2):
1. **Three timbres per note** (harmonic decays 0.4 / 0.65 / 0.85) in the note estimator, so a bright
   bass's overtones are not left over as ghost notes.
2. **Melody first:** a top voice well above at least three other notes counts weakly. Note strength is
   then judged against the accompaniment, so a loud melody cannot hide quiet accompaniment.

**Tried and reverted:** discounting notes an octave / octave + fifth / two octaves above the bass as
bass overtones. It removed the root (chords double the bass), and minor A fell from 47/47 to 12/47.
Also reverted: requiring only two notes below a melody, which made the top chord tone a "melody".

**New:**
- **Accompaniment-stem mode.** Harmony runs on the separated backing part (the benchmark leaves 20%
  melody and drum leakage); beats still come from the mix.
- **Held-out 3:** 110 BPM, every song transposed up 3 semitones, other instruments. Run once and
  **never tuned on**.

| Beat accuracy (target ≥ 85%) | Current | Hypotheses on mix | **Hypotheses on accompaniment stem** |
|---|---|---|---|
| In-sample | 73% | 90% | **93%** |
| Held-out 1 | 59% | 88% | **88%** |
| Held-out 2 | 66% | 80% | **86%** |
| **Held-out 3 (untouched)** | **46%** | **81%** | **83%** |

Held-out 3, other measures (current / mix / stem):

| Measure | Current | Mix | Stem | Target |
|---|---|---|---|---|
| Minor keys | 26% | 91% | **100%** | ≥ 75% |
| Half-bar changes | 62% | 100% | **100%** | — |
| Drone labelled drone | 0% | 0% | **100%** | ≥ 90% |
| Truth in alternatives | 50% | 91% | **94%** | ≥ 95% |

Speed: 3.12 s per 4-minute song (budget < 10 s). Core tests: 215, 0 failures.

**Known weaknesses on held-out 3** (same on mix and stem):
- Inversions with clavinet: 15/47.
- Pedal bass with tremolo strings: 23/47.

Both involve the bass carrying a non-root note. They are not tuned further, because no untouched
set would be left.

**Gate status:**
- Clearly better than the current analyzer on every set.
- On the untouched set with stems, 3 of 4 targets are met. Overall accuracy is 83% (target 85%) and
  alternatives 94% (target 95%), so both are just short.
- Real audio: 0 clips.

**Decision: still not switched on.** Recommended path: use the accompaniment stem when the song
has been separated; keep the current analyzer otherwise until real-audio acceptance.

**Data note (owner's message):** the owner suggested training on songs from masstamilan.dev. That is
a piracy site, which the project's standing rule excludes (no downloads from piracy sites, no ripped
MP3s). Legal sources were proposed instead: owner recordings, CC BY / CC0 tracks, recordings by
permission.
