# Core ML deployment report — EfficientAT mn10_as (Gate 2)

**Status:** Mac CI measured; **physical iPhone pending** (TonePilot Lab ready to build). Not a
production selection. Machine-readable results: `COREML_DEPLOYMENT_RESULTS.json` (branch `ci/coreml-gate2`).

| Label | Meaning |
|---|---|
| **Measured (Mac CI)** | GitHub `macos-26` Apple-silicon runner, run 41323484719 (shared, noisy machine) |
| **Estimated** | Derived from Mac measurements (full-song = windows × per-window time) |
| **Pending (iPhone)** | Needs one TonePilot Lab run on a physical iPhone |

## Gate 2 status (2 Nov 2026)

| Requirement | Status | Label |
|---|---|---|
| Core ML conversion (fp32, fp16, int8; 6-bit rejected) | Passed | Measured on Mac CI |
| Numerical consistency (max/mean/RMSE, cosine, top-k, family and decision agreement) | Passed (fp16 99.5% family-decision agreement) | Measured on Mac CI |
| Mac inference performance (about 4 ms per 1 s window, fp16) | Measured | Measured on Mac CI (not iPhone) |
| Inference contract in the full build (Basic Pitch test model: all units 28.3 ms, CPU only 44.8 ms, max error 9.5e-7) | Passed | Measured on Mac CI. One test-model call, **not** a full-song or iPhone time |
| Swift mel front-end parity (2.2e-5 vs PyTorch) and speed (0.12 s per 4-min song, Accelerate) | Passed | Measured on Mac CI / Linux |
| Shadow-mode own work (front-end + head, no Core ML): 2.42 s per 4-min song | Measured | Measured on Linux CI |
| Actual iPhone latency (cold/warm, median/p90/p95) | **Pending** | Physical iPhone run of TonePilot Lab (G2.4) |
| Full-song analysis time on a physical iPhone (1/3/4/5 min) | **Pending** | same |
| Physical-device peak memory | **Pending** | same |
| Battery behaviour | **Pending** | same (1–5% granularity; precise energy isn't exposed to apps) |
| Thermal behaviour | **Pending** | same |
| Shadow-mode validation on real songs | **Pending** | Developer-only; needs G2.4 and the head/model files on the device |

No physical iPhone is connected to this project's CI. The pending rows stay pending until the owner runs TonePilot Lab and shares the JSON. Nothing in this report is an estimate of iPhone performance.

## Variants (measured, Mac CI; ~200 real benchmark windows: clean, reverb, compressed, layered, silence, −40 dB)

| Variant | Size | Warm median (ms per 1 s window) | Max abs diff (probs) | Embedding cosine (min) | Top-1 agreement | Family-decision agreement | Verdict |
|---|---|---|---|---|---|---|---|
| fp32 | 19.6 MB | 3.4–5.1 | 3e-6 | 1.00000 | 100% | 100% | Reference |
| **fp16** | **9.9 MB** | 4.0–4.7 | 2.2e-2 | 0.99999 | 100% | **99.5%** | **Recommended candidate** |
| int8 weights | 5.1 MB | 3.0–4.3 | 5.5e-2 | 0.99995 | 100% | 97.2% | Possible "small" option, more decision drift |
| 6-bit palettised | 3.8 MB | 4.2–6.2 | 2.4e-1 | 0.99871 | 100% | 87.2% | **Rejected** (changes decisions) |

- **Compute units** (CPU only / CPU + Neural Engine / all): no consistent winner on the Mac runner;
  differences are within runner noise (p95 up to 13 ms). The iPhone decides.
- **Cold start** (load + first prediction): 300–470 ms per model and unit.
- **Full song, inference only (estimated from Mac):** 4 min ≈ 1.3–1.6 s at 0.5 s hop.
- **Front-end (Swift mel, measured Linux CPU):** matches PyTorch to 2.2e-5. 2.6 s per 4-min song after
  the sparse-band optimisation; **with the Accelerate (vDSP) path on Apple platforms: 0.12 s per 4-min song**
  on the Mac runner, same accuracy (2.2e-5). Inference is now the larger stage.

## End-to-end stages (4-min song)

| Stage | Cost | Status |
|---|---|---|
| Decode + resample to 32 kHz | — | Pending (iPhone; uses existing app decoder) |
| Mel front-end (Swift) | **0.12 s with Accelerate (Mac runner)**; 2.5 s portable path (Linux) | Measured (Mac/Linux); iPhone pending |
| Core ML inference (fp16) | ~1.3–1.6 s | Estimated (Mac) |
| Heads + calibration + time aggregation | < 0.1 s (logistic heads) | Estimated |

## Physical iPhone (pending)

TonePilot Lab (`Lab/`, separate app; the main app is untouched) measures on the device:
- cold and warm latency per compute unit (median, p90, p95);
- full-song time for 1, 3, 4 and 5 minutes;
- memory footprint;
- thermal state every 5 s;
- battery before and after a 1- or 5-minute sustained run;
- on-device front-end and Core ML parity against PyTorch.

**Owner action:** sideload `TonePilotLab.ipa` (Actions artifact from `lab-build.yml`), press **Full run**
unplugged, share the JSON.

## Reproduce

1. Run `coreml-gate2.yml` (input: an `instrument-bench` run id; runner `macos-26`).
2. Then `lab-build.yml` (input: that Gate 2 run id).
