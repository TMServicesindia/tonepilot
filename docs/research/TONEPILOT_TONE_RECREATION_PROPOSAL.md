# TonePilot — Tone Recreation: instrument identity + perceptual tone search (research proposal)

**Date:** 2 November 2026. **Status: PROPOSAL ONLY.** No implementation, no model training, no app or build change. Benchmark splits and the sealed 20-song TEST catalogue are unchanged.

**Owner direction (2 Nov):** instrument identity and perceptual tone matching are different problems. A confident identity must never restrict the tone search. The goal is to **recreate the sound** on a CT-X870IN, not necessarily to reproduce the original instrument.

## 1. Audit of the current implementation (verified from code, 2 Nov)

| Stage | Where | What it does today | Measured weakness |
|---|---|---|---|
| Instrument evidence | `App/Sources/Audio/InstrumentRecognizer.swift` | Apple SoundAnalysis → 13 production families per section | No Indian families; the owner's real-song test was poor |
| Lead tone per section | `AutoArranger.rankLeads` | Score = 45% heard family + 30% intensity + 25% timbre heuristics (centroid, sustain, ornaments, register) | Family evidence dominates, so a wrong family means a wrong tone |
| Measured tone override | `PartMatcher` → `ToneMatcher` | For each separated part, on **one** important section: extract notes, play them on **14 tag-chosen** candidates, compare fingerprints, fit 3-band EQ + reverb. Overrides the arranger when similarity ≥ 0.62 | The pre-selection dropped the true sound in 8/12 bench songs; the fingerprint doesn't carry across sound sources |
| Main tone | `AutoArranger.aiMainTone` | The lead that covers the most weighted song time (chorus ×2, climax ×1.3, loudness), copied from its most intense section | Inherits the errors above; one part-match for the whole song, so pallavi and charanam aren't matched separately |
| Fingerprint | `ToneMatcher.fingerprint` | 24 log bands (80 Hz–12 kHz, pitch-synchronous at the harmonics), attack, sustain, tail, noise | Sample-specific band shape. Another bank's flute or violin lands closer to our brass |

**Measured (core bench, `INSTRUMENT_PROXY_RESULTS.md`, "Tone recreation" section):**
- **Same bank:** lead 4/12 exact, 7/12 family.
- **Sealed cross-bank TEST:** lead 0/12 exact, 3/12 family; backing 0/12, 1/12.
- **Whole-library screening (branch `research/tone-shortlist`):** same-bank lead 8/12 exact, 9/12 family, but no gain on the sealed TEST, and 2× slower.

## 2. Two recommendations, never one gating the other

| Recommendation | Question | Signal | Shown as |
|---|---|---|---|
| **A. Instrument match** | "What instrument is this?" | Identity model (EfficientAT + head C, abstaining; the production recognizer stays authoritative until gates pass) | Family / instrument / "unknown" + confidence |
| **B. Perceptual tone match** | "Which of my tones *sounds* closest?" | Perceptual search over **the whole library**, all families | Top 3 tones (or layers) + similarity + why |

**How they combine:**
- **They agree** (B's best tone belongs to A's family): high confidence; show one recommendation.
- **They disagree:** show both. "Sounds like: Soft Synth Lead · Instrument: flute (likely)". Your example: a synth string patch heard as "violin" still gets the synth-strings tone from B.
- **A abstains:** B alone. That is still useful: recreating the sound doesn't require naming it.
- **A never removes candidates from B.** It may only re-order *ties* (B's similarity within a small margin).

**Source type** (acoustic / electronic / imitation; currently weak, 31/60 imitations) is shown as a hint, never used as a filter.

## 3. Why perceptual search fails today, and the proposed fix

The fingerprint compares the exact 24-band shape, which is an identity of the *sample*. A perceptual measure should keep only what a listener hears as "the sound" and tolerate what differs between recordings of similar sounds.

**Proposed perceptual descriptor** (computed on the part's notes, pitch-synchronous as today):

| Descriptor | Captures | Why it should transfer across sources (hypothesis) |
|---|---|---|
| Smoothed spectral envelope (about 8 bands, or cepstral coefficients 1–8, after allowing the same 3-band EQ the app can apply) | Formant / body colour | Fine sample detail removed; the EQ the app can fix is ignored |
| Brightness relative to f0 (centroid / f0) | Bright vs dark | Register-independent |
| Attack time + attack noise burst | Plucked / blown / bowed / struck | Physical excitation class |
| Decay shape (sustain at 30 / 70%, tail) | Piano-like decay vs held tone | Excitation class |
| Breath / bow noise (flatness between harmonics) | Airy vs clean | Perceptually salient |
| Pitch behaviour (vibrato depth/rate, glides) | Singing leads vs keys | Hints at technique; needs the matching technique on the keyboard |

Note: the harmonic-profile feature tried on 2 Nov did not help on its own. These descriptors must be **tested one at a time** (ablation on DEV), not adopted on argument.

**Speed: a precomputed tone table** (the key enabler for a whole-library search):
- Render every library tone **once** (offline or in CI) at about 6 pitches × 2 note lengths.
- Store its descriptors (a few KB per tone; the whole library well under 1 MB).
- At analysis time, compare the target's descriptors with the table: **no rendering**, so the whole library is searched in milliseconds.
- Then render only the top 6 for the existing full check and the EQ/reverb fit.
- This removes the 2× slowdown measured for the screening prototype (INFERENCE; to be measured).

## 4. Recreate the nearest sound: fit the chosen tone to the song

**Goal (owner, 2 Nov):** the **nearest sound to the song's own part**. TonePilot recreates it with its own engine; it does not depend on the Casio's built-in tones (those are extra candidates, §4c).

**Step 1. Find the nearest tone:** the perceptual search over the whole library (§3, T1).

**Step 2. Shape that tone towards the part.** TonePilot's engine can change, per layer:
- attack, decay, sustain, release;
- low-pass filter cutoff and resonance;
- 3-band EQ;
- reverb, chorus and delay sends;
- octave;
- vibrato depth and rate;
- glide.

The fit:
- The existing matcher already fits EQ and reverb.
- The proposal extends it to **attack / release, filter brightness and vibrato**, measured on the part's own notes.
- Each parameter is kept only when the re-rendered tone measurably moves closer to the part (re-measured, as the EQ fit already is).

**Output:** one tone with its fitted settings, saved as the section's tone or the song's main tone. It is played from the Casio over MIDI through TonePilot's engine.

## 4b. Layering: can two tones recreate a complex sound? (restored, owner 2 Nov)

**Search:**
- From the top 6 candidates (B), try **pairs** (15 pairs) with level ratios {0.3, 0.5, 0.7} and octave offsets {0, +12}: 90 combinations.
- Score with the same perceptual measure, after the fit in §4.
- Report the gain over the best single fitted tone.

**Guardrails:**
- A layer is recommended only if it beats the best single tone by a margin set on DEV.
- At most 2 layers (TonePilot's engine allows 8; 2 keeps it playable and predictable).

**Output, the tone setup:**
- base tone + fitted settings;
- optional layer tone + level + octave;
- reverb/chorus;
- playing technique (e.g. grace notes for gamaka, legato, pedal).

## 4c. Casio CT-X870IN tones (owner, 2 Nov: no manual recording)

- **Manual recording is removed from the plan.**
- TonePilot's measured recommendation is always one of **its own tones** (playable from the owner's keyboard through the app).
- Casio tones can be suggested only **by name/category mapping** from the owner's tone list. They are labelled "by name, not measured".
- An optional future *automatic* capture (program changes + notes over MIDI out, Casio audio into an interface; no playing) is noted in [`benchmark/OPEN_SOURCE_TONE_REFERENCE_EXPANSION_PLAN.md`](../benchmark/OPEN_SOURCE_TONE_REFERENCE_EXPANSION_PLAN.md) §6.
- The Casio's internal samples are never extracted.

## 5. "Simple-instrument recreation" evaluation (PianistRam-style; future)

Goal: test whether TonePilot can recommend a *convincing* keyboard sound for a part, the way skilled players imitate film instruments with piano or simple keyboard tones. **No video was analysed; we have no audio access to them, and YouTube audio is excluded by project rules.**

**Lawful data:**
- the owner records (a) a reference phrase from their own instrument or a permitted source, and (b) their keyboard recreation;
- or volunteer musicians, with written permission.

**Metric:** owner listening ranks.
- Per target, the owner hears TonePilot's top-3 tones (with fitted settings) and today's choice, plus the best layer and the nearest Casio tone, then ranks them (or rates 0–100, MUSHRA-style, blind order).
- **Success:** TonePilot's top-1 fitted tone is ranked ≥ today's choice in ≥ 70% of targets (proposed gate).

## 6. Evaluation plan (splits preserved)

| Set | Use | Status |
|---|---|---|
| Same-bank renders (GeneralUser) | DEV (sanity: exact sample available) | Exists |
| Cross-bank TimGM6mb renders | DEV (unseen source) | Exists |
| Cross-bank FluidR3 renders | **Sealed TEST.** Run once each for the old matcher and the screening prototype on 2 Nov; still untouched by tuning, but each further use spends it | Exists |
| **New sealed TEST bank** | For the next method decision | **Needed:** a third GM bank with a verified licence (candidate: MuseScore General; licence to verify) |
| Owner listening set (§5) | Perceptual acceptance | Needs recordings |
| 20-song catalogue | Sealed real-world TEST | Unchanged; never tuned on |

**Metrics, always reported separately:**
- identity: family / exact / abstain;
- perceptual: descriptor distance, plus owner rank on the listening set;
- fitting gain (similarity before vs after shaping the tone);
- layering gain (best pair vs best single fitted tone);
- Casio vs TonePilot: how often a Casio tone is the nearest;
- time per part (Linux CI, plus iPhone once G2.4 runs).

## 7. Proposed experiments (for approval; none started)

| ID | Question | Data | Gate to proceed |
|---|---|---|---|
| T1 | Does a descriptor-table search (no rendering) match the current fingerprint on same-bank DEV, and beat it on cross-bank DEV? | GU + TimGM6mb | Cross-bank family ≥ +3/12 with same-bank not worse |
| T2 | Which descriptors carry across sources? (one-at-a-time ablation) | Cross-bank DEV | Keep only features that help |
| T3 | Does fitting attack / release, filter and vibrato to the part move the chosen tone measurably closer? | Cross-bank DEV + owner listening | Similarity gain on DEV in ≥ 50% of targets, no target worse |
| T3b | Do two-tone layers beat the best single fitted tone? | DEV + owner listening | Gain > DEV margin in ≥ 30% of targets |
| T6 | (Deferred) Casio tones measured by automatic capture, if MIDI out + an audio cable become available | — | Report only |
| T4 | Agreement / disagreement between A (identity) and B (perceptual): how often, and which one is right? | Cross-bank DEV with known instruments | Report only |
| T5 | Owner listening test (§5) | Owner recordings | ≥ 70% ranked ≥ today's choice |

**Not proposed:** more training to push EfficientAT from 86% to 90% on synthetic clean clips (owner agreed this is low value now).
