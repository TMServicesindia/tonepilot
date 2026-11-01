# Core ML deployment report — EfficientAT mn10_as (Gate 2)

**Status:** Mac CI measured; **physical iPhone pending** (TonePilot Lab ready to build). Not a
production selection. Machine-readable results: `COREML_DEPLOYMENT_RESULTS.json` (branch `ci/coreml-gate2`).

| Label | Meaning |
|---|---|
| **Measured (Mac CI)** | GitHub `macos-26` Apple-silicon runner, run 41323484719 (shared, noisy machine) |
| **Estimated** | Derived from Mac measurements (full-song = windows × per-window time) |
| **Pending (iPhone)** | Needs one TonePilot Lab run on a physical iPhone |

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
  the sparse-band optimisation, so **the front-end now costs more than inference**. Next: an
  Accelerate (vDSP) FFT path on iOS.

## End-to-end stages (4-min song)

| Stage | Cost | Status |
|---|---|---|
| Decode + resample to 32 kHz | — | Pending (iPhone; uses existing app decoder) |
| Mel front-end (Swift) | 2.6 s Linux CPU | Measured (Linux); iPhone pending |
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
