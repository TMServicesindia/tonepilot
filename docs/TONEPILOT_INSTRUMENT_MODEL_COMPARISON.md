# TonePilot — Instrument Model Comparison (audit + challenger plan)

**Date:** 2 November 2026. **Status:** audit of existing results plus a proposed protocol. **No model selection changes.**

**The official candidate stays EfficientAT mn10_as + TonePilot head C, with DEV-selected thresholds** (owner decision, 2 Nov).

**Labels:**
- **MEASURED-SYN** = measured by TonePilot on synthetic proxy data (GM renders, synthesised imitations);
- **MEASURED-NSYNTH** = measured on NSynth-test (real recorded notes, not music mixtures);
- **MEASURED-MAC** = Mac CI timing;
- **PUBLISHED** = the authors' own figure;
- **NOT TESTED**;
- **PENDING** = needs a physical iPhone.

## 1. What the repository actually contains (verified from code, 2 Nov)

| Component | Where | Facts |
|---|---|---|
| Production recognizer | `App/Sources/Audio/InstrumentRecognizer.swift` | Apple SoundAnalysis `.version1`, overlap 0.25; maps labels to 13 `InstrumentEvidence` families (no Indian instrument families); mean confidence per section; runs on separated parts when they exist |
| Research candidate | `Native/tools/instruments/embed.py` + `calibrate.py` | EfficientAT `mn10_as` (pretrained AudioSet weights, **frozen**); embeddings → scikit-learn logistic heads (instrument and family multi-label, source multi-class; `C=0.5`, class-balanced); **no fine-tuning of the network** |
| Mel front-end | `EfficientATFrontEnd.swift` | Matches PyTorch to 2.2e-5 (Linux/macOS) |
| Core ML | `convert_efficientat.py`, `gate2_coreml.py` | fp16 9.9 MB, 99.5% family-decision agreement vs fp32, about 4 ms per 1 s window (MEASURED-MAC); int8 5.1 MB, 97.2%; 6-bit rejected (87.2%) |
| Shadow mode | `DeveloperShadowMode.swift`, `ShadowInstruments.swift` | Developer-only, off by default, files-gated; never alters output. **Not yet built into an app build.** On-device validation PENDING |
| Taxonomy | `Native/tools/instruments/taxonomy.json` v2 | 13 families, 72 keys, sources acoustic / electronic / imitation / unknown |
| Other benchmarked models | `embed.py` | YAMNet (TF Hub); **PANNs = `panns_inference` default, i.e. CNN14** (about 81 M parameters, INFERENCE from the library default; CNN10 **NOT TESTED**); LAION-CLAP music (10 s windows) |

## 2. Existing results (preserved; not reinterpreted)

All from `docs/benchmark/INSTRUMENT_PROXY_RESULTS.md`. TEST = GeneralUser GS renders (untouched) unless noted.

| Benchmark | EfficientAT + head C (coverage / wrong family / selective family acc.) | Notes |
|---|---|---|
| v2 clean (MEASURED-SYN) | 41% / 3% / 94% | GM-only training |
| v3 NSynth-test (MEASURED-NSYNTH) | 47% / 6% / 87% | + NSynth training notes |
| v4 clean (MEASURED-SYN) | 72% / 10% / 86% | + synthesised imitations |
| v4 1 s clips | 95% / 25% / 73% | Confidently wrong on short clips |
| v4 imitation tones | 78% / 22% / 72% | |
| v4 NSynth-test | 50% / 7% / 87% | |
| v4 source type (corrected 2 Nov) | imitation: 31 imitation / 28 acoustic / 1 electronic (of 60) | Weak distinction, about half recognised. The earlier "never says imitation" came from a truncated log line |
| v4 layered (window instrument F1 / family F1; onset error median / p90) | 0.34 / 0.50; 0.5 s / 7.0 s | 46/70 events detected |
| v4b C-agree (not adopted) | NSynth 24% / 9% / 61%; 1 s clips 60% / 7% / 88% | Worse on real notes; DEV rule keeps C |

Other models (v4, TEST clean; MEASURED-SYN):
- PANNs-CNN14 + head: 85% / 26% / 70%.
- YAMNet + head: 55% / 11% / 80%.
- CLAP + head: 3% coverage.
- Apple SoundAnalysis: 14/19 clean instruments in the earlier CI check.

**The ≤ 5% wrong-family target is not met on every condition. There is no measurement on real Indian music.**

## 3. Candidates

| Model | Code / weights licence | Size | Published AudioSet mAP | iPhone fit | Role |
|---|---|---|---|---|---|
| **EfficientAT mn10_as** | MIT (SECONDARY: downstream conversions cite MIT; upstream LICENSE to re-check); AudioSet label names CC BY-SA 4.0 | **4.88 M params**, 9.9 MB fp16 Core ML | 0.471 (single best checkpoint; repo table averages about 0.46–0.47) (PUBLISHED) | **Proven conversion** (MEASURED-MAC) | **Primary baseline** |
| PANNs **CNN10** | MIT code; weights CC BY 4.0 (Zenodo 3987831, existing register) | **5.2 M params** (SECONDARY table) | 0.380 (PUBLISHED via secondary table) | Likely (a plain CNN); conversion NOT TESTED | **Next challenger, at equal size** |
| PANNs CNN14 | as above | about 81 M params | 0.431 (PUBLISHED) | Heavy for on-device full-song use (INFERENCE) | Comparison only (already benchmarked) |
| YAMNet | Apache-2.0 (TF Hub) | about 3.7 M params (INFERENCE from MobileNet-v1 size) | — | Yes (small) | Low-cost comparison (already benchmarked) |
| BEATs | Licence **UNKNOWN** (repo says "LICENSE file in root"; microsoft/unilm, to check) | Transformer, ViT-base scale (INFERENCE; NOT VERIFIED) | 50.6% on AS-2M (PUBLISHED, ICML 2023) | Doubtful for full songs on device (INFERENCE) | **Research challenger: frozen embeddings only**, after a licence check |
| Apple SoundAnalysis | Apple SDK | Built in | — | Yes (production) | Comparison and fallback, **not ground truth** |

## 4. Why the current results fail, and what that implies (INFERENCE from the measured results)

1. **Domain gap, not threshold choice.** Training on NSynth real notes raised real-note accuracy from 33% to 87%; threshold variants (v4b) traded one domain for another. → **Real, permissive Indian-domain data is the lever** (Sanidha first).
2. **Frozen AudioSet embeddings + linear heads** under-use the data for fine timbre distinctions such as nadaswaram vs shehnai, or sarangi vs violin. → After the data improves, test (a) a small MLP head and (b) partial fine-tuning of the last blocks on a free GPU session, both against DEV only.
3. **Short and layered windows:** one 1 s window gives overconfident heads. → Multi-resolution pooling (1 s and 3 s context) and **temporal smoothing** of activity before deciding entry and exit.
4. **Source type:** with no paired acoustic/imitation data, the head cannot learn the distinction. → Paired recordings (real instrument and Casio, same phrase).

## 5. Pre-declared comparison protocol (proposed for owner approval)

- **Same data, splits, preprocessing (32 kHz mono, 1 s / 0.5 s hop) and heads** for every model. Only the frozen encoder changes.
- **Selection on DEV only.** TEST is reported **once** per declared experiment. **A challenger replaces C only if** it beats C on DEV on the primary metric *and* does not lose on the guard metrics.
  - **Primary metric:** family macro-F1 at the coverage where wrong-family ≤ 5%.
  - **Guard metrics:** NSynth-test wrong-family, layered window F1, and the Sanidha DEV session.
  - The result is then confirmed on TEST.
- **Metrics reported for every model:**
  - exact-instrument and family macro-F1;
  - mAP;
  - per-class precision and recall;
  - wrong-family rate;
  - selective accuracy at 30–100% coverage;
  - ECE calibration error;
  - layered window F1;
  - event F1 and onset/offset error (median, p90);
  - size, Core ML feasibility, and iPhone latency (PENDING).
- **Confidence intervals:** bootstrap over recordings (not windows), because windows within a recording are correlated.
- **Results always kept separate by domain:**
  - synthetic (GM);
  - NSynth;
  - real Indian classical (Sanidha);
  - real film (acceptance).

## 6. Recommendation

1. **Keep C as official.** Its known weaknesses are data problems, not model problems.
2. **Next challenger: PANNs CNN10** (same size class as EfficientAT, permissive weights, never tested). Run it as an add-on to the existing bench matrix, which is a small change.
3. **BEATs:** licence check first; frozen embeddings only; it doesn't block anything.
4. **First data experiment:** Sanidha session-disjoint evaluation of the existing frozen encoders (C, CNN10, YAMNet), with stem-derived activity labels after a human spot-check (see the roadmap, E1).

## 7. E2 result (2 Nov, run 41386940981; synthetic proxy + NSynth)

**PANNs CNN10 did not beat EfficientAT + head C** under the pre-declared protocol:

| Metric | CNN10 | EfficientAT + C |
|---|---|---|
| DEV coverage at ≤ 5% wrong-family | 60% | **73%** |
| NSynth-test coverage | 24% | **50%** |
| Layered instrument F1 | 0.28 | **0.35** |
| CPU time per audio minute | 2.0 s | **0.44 s** |

**C stays official.** Details: `benchmark/INSTRUMENT_PROXY_RESULTS.md` (E2 section).

**Next challenger:** BEATs (after a licence check), or E1 on real Indian audio. A model challenge on synthetic data alone is now of low value.
