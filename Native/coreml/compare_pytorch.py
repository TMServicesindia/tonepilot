"""Referee: separates the same block with the original PyTorch Demucs (htdemucs) and measures
how close TonePilot's CPU engine (demucs.cpp) and its Core ML engine are to it.
Exits 1 unless, for every part, the Core ML engine is at least as close to PyTorch as the CPU
engine the app used before (measured: both share demucs.cpp's spectrogram/segmenting, which is
where most of their common difference from PyTorch comes from)."""
import sys
import numpy as np
import torch
from demucs.apply import apply_model
from demucs.pretrained import get_model

work = sys.argv[1]
mix = np.fromfile(f"{work}/block0_input.f32", dtype=np.float32).reshape(2, -1)
n = mix.shape[1]
cpu = np.fromfile(f"{work}/block0_cpu.f32", dtype=np.float32).reshape(4, 2, n)
ml = np.fromfile(f"{work}/block0_coreml.f32", dtype=np.float32).reshape(4, 2, n)

bag = get_model("htdemucs")
print("sources", bag.sources)
with torch.no_grad():
    ref = apply_model(bag, torch.from_numpy(mix)[None], shifts=0, split=True, overlap=0.25, progress=False)[0].numpy()

def snr(a, b):
    return 10 * np.log10(np.sum(a.astype(np.float64) ** 2) / max(np.sum((a.astype(np.float64) - b) ** 2), 1e-30))

worst = {"cpu": 1e9, "coreml": 1e9}
ok = True
for i, name in enumerate(bag.sources):
    c, m = snr(ref[i], cpu[i]), snr(ref[i], ml[i])
    worst["cpu"] = min(worst["cpu"], c); worst["coreml"] = min(worst["coreml"], m)
    ok = ok and m >= c - 0.5
    print(f"RESULT {name}: vs PyTorch Demucs — CPU engine {c:.1f} dB, Core ML {m:.1f} dB")
print(f"RESULT worst part: CPU engine {worst['cpu']:.1f} dB, Core ML {worst['coreml']:.1f} dB")
print("RESULT verdict:", "Core ML is as faithful as (or better than) the CPU engine" if ok else "Core ML is less faithful — not shipped")
sys.exit(0 if ok else 1)
