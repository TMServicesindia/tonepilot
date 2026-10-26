"""Pinpoints where the engines differ, on the first segment of the app's own separation run:
feeds the exact network inputs demucs.cpp produced to the original PyTorch network and
compares both engines' network outputs with it (and Core ML via coremltools, to check the
app's Swift wrapper). Usage: compare_network.py <dump dir> <HTDemucs.mlpackage>"""
import os, sys
import numpy as np
import torch

sys.path.insert(0, os.path.dirname(__file__))
from convert_htdemucs import Core, m, snr  # noqa: E402

d, pkg = sys.argv[1], sys.argv[2]
F, T, L = 2048, 336, 343980
load = lambda n, shape: np.fromfile(f"{d}/{n}", dtype=np.float32).reshape(shape)
x, xt = load("cpu_x.f32", (1, 4, F, T)), load("cpu_xt.f32", (1, 2, L))
mx, mxt = load("ml_x.f32", (1, 4, F, T)), load("ml_xt.f32", (1, 2, L))
print(f"RESULT inputs identical in both engines: x {np.abs(x - mx).max():.2e}, xt {np.abs(xt - mxt).max():.2e}")
after = load("ml_x_after.f32", (1, 4, F, T))
print(f"RESULT Core ML left its input unchanged: max change {np.abs(after - mx).max():.2e}")

with torch.no_grad():
    rx, rxt = (t.numpy() for t in Core(m).eval()(torch.from_numpy(x), torch.from_numpy(xt)))
cx, cxt = load("cpu_x_out.f32", (1, 16, F, T)), load("cpu_xt_out.f32", (1, 8, L))
ax, axt = load("ml_x_out.f32", (1, 16, F, T)), load("ml_xt_out.f32", (1, 8, L))
print(f"RESULT network vs PyTorch — CPU engine: spec {snr(rx, cx):.1f} dB, wave {snr(rxt, cxt):.1f} dB")
# The engines may hand over different first segments, so the app's Core ML output is judged
# against PyTorch on its own inputs.
with torch.no_grad():
    mrx, mrxt = (t.numpy() for t in Core(m).eval()(torch.from_numpy(mx), torch.from_numpy(mxt)))
print(f"RESULT network vs PyTorch — Core ML in the app (its own inputs): spec {snr(mrx, ax):.1f} dB, wave {snr(mrxt, axt):.1f} dB")

import coremltools as ct  # noqa: E402
for units in ["CPU_ONLY", "ALL"]:
    r = ct.models.MLModel(pkg, compute_units=getattr(ct.ComputeUnit, units)).predict({"x": x, "xt": xt})
    print(f"RESULT coremltools {units} vs PyTorch: spec {snr(rx, r['x_out']):.1f} dB, wave {snr(rxt, r['xt_out']):.1f} dB;"
          f" vs the app's Core ML output: spec {snr(r['x_out'], ax):.1f} dB")
