# Core ML deployment — Gate 2 results (EfficientAT mn10_as)

**All timings are MAC CI measurements (macos-15-intel / Intel(R) Core(TM) i7-8700B CPU @ 3.20GHz) or estimates from them — NOT iPhone results.**
Validation windows: 218 ({'compressed': 64, 'layered': 24, 'minus40dB': 1, 'original': 64, 'reverb': 64, 'silence': 1}). Reference: PyTorch fp32. Family decisions via a logistic head trained on the FluidR3 train bank.

| Variant | Size MB | Units | Cold load+1st (ms) | Warm median / p90 / p95 (ms) | Best ms/window | 4-min song est. (s) | Max abs diff | Emb. cosine min | Top-1 agree | Family agree |
|---|---|---|---|---|---|---|---|---|---|---|
| fp32 | 19.58 | cpuOnly | 622.2 | 12.077 / 12.821 / 13.148 | 5.70 | 2.74 | 3.0e-06 | 1.00000 | 100.0% | 100.0% |
| fp32 | 19.58 | cpuAndNE | 567.5 | 11.284 / 12.637 / 13.08 | 5.91 | 2.84 | 3.0e-06 | 1.00000 | 100.0% | 100.0% |
| fp32 | 19.58 | all | 948.2 | 11.012 / 12.26 / 12.528 | 5.95 | 2.85 | 3.0e-06 | 1.00000 | 100.0% | 100.0% |
| fp16 | 9.86 | cpuOnly | 598.1 | 14.423 / 15.729 / 15.906 | 5.86 | 2.81 | 7.5e-03 | 1.00000 | 100.0% | 100.0% |
| fp16 | 9.86 | cpuAndNE | 542.3 | 13.173 / 14.365 / 14.63 | 6.32 | 3.03 | 7.5e-03 | 1.00000 | 100.0% | 100.0% |
| fp16 | 9.86 | all | 560.3 | 13.266 / 14.728 / 14.98 | 5.85 | 2.81 | 7.5e-03 | 1.00000 | 100.0% | 100.0% |
| int8-weights | 5.09 | cpuOnly | 706.5 | 13.819 / 15.283 / 15.455 | 6.34 | 3.04 | 4.7e-02 | 0.99995 | 100.0% | 97.2% |
| int8-weights | 5.09 | cpuAndNE | 705.1 | 13.346 / 14.453 / 14.634 | 6.49 | 3.11 | 4.7e-02 | 0.99995 | 100.0% | 97.2% |
| int8-weights | 5.09 | all | 773.1 | 12.837 / 15.131 / 15.755 | 6.56 | 3.15 | 4.7e-02 | 0.99995 | 100.0% | 97.2% |
| palettized-6bit | 3.84 | cpuOnly | 574.5 | 13.426 / 14.669 / 15.003 | 5.90 | 2.83 | 2.4e-01 | 0.99872 | 100.0% | 86.2% |
| palettized-6bit | 3.84 | cpuAndNE | 644.6 | 12.996 / 14.013 / 14.541 | 6.03 | 2.89 | 2.4e-01 | 0.99872 | 100.0% | 86.2% |
| palettized-6bit | 3.84 | all | 626.5 | 12.924 / 14.358 / 15.027 | 5.98 | 2.87 | 2.4e-01 | 0.99872 | 100.0% | 86.2% |

Flexible batch: True. Params: 4876831. Front-end fixture written for the Swift mel implementation.
