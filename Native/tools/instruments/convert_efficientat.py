"""Research only (macOS CI): EfficientAT mn10_as → Core ML. The network part (mel spectrogram in,
AudioSet logits + embedding out) is converted; the mel front-end will be reproduced in Swift and
checked against fixtures, as was done for Beat This!. Reports numeric difference vs PyTorch, file
size (fp32/fp16) and Core ML prediction time (CPU / all compute units).
Usage: convert_efficientat.py <EfficientAT repo> <out dir>"""
import json, os, sys, time
import numpy as np
import torch

repo, out = sys.argv[1], sys.argv[2]
sys.path.insert(0, repo); os.chdir(repo)
from models.mn.model import get_model
from models.preprocess import AugmentMelSTFT
from helpers.utils import NAME_TO_WIDTH
import coremltools as ct

name = "mn10_as"
model = get_model(width_mult=NAME_TO_WIDTH(name), pretrained_name=name).eval()
mel = AugmentMelSTFT(n_mels=128, sr=32000, win_length=800, hopsize=320).eval()
rng = np.random.default_rng(0)
wave = torch.from_numpy((rng.standard_normal(32000) * 0.1).astype(np.float32))[None]
with torch.no_grad():
    spec = mel(wave).unsqueeze(1)               # [1, 1, 128, T]

class Net(torch.nn.Module):
    def __init__(self, m): super().__init__(); self.m = m
    def forward(self, x):
        logits, feats = self.m(x)
        return torch.sigmoid(logits), feats.reshape(x.shape[0], -1)

net = Net(model).eval()
with torch.no_grad():
    ref_p, ref_e = net(spec)
    traced = torch.jit.trace(net, spec)
os.makedirs(out, exist_ok=True)
report = {"model": name, "params": int(sum(p.numel() for p in model.parameters())), "input_shape": list(spec.shape)}
for prec in ("float32", "float16"):
    ml = ct.convert(traced, inputs=[ct.TensorType(name="mel", shape=tuple(spec.shape), dtype=np.float32)],
                    outputs=[ct.TensorType(name="probs"), ct.TensorType(name="embedding")], convert_to="mlprogram",
                    compute_precision=ct.precision.FLOAT32 if prec == "float32" else ct.precision.FLOAT16,
                    minimum_deployment_target=ct.target.iOS16)
    path = os.path.join(out, f"EfficientAT_{name}_{prec}.mlpackage"); ml.save(path)
    size = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(path) for f in fs)
    for label, units in (("cpuOnly", ct.ComputeUnit.CPU_ONLY), ("all", ct.ComputeUnit.ALL)):
        m = ct.models.MLModel(path, compute_units=units)
        o = m.predict({"mel": spec.numpy()})
        t0 = time.time()
        for _ in range(20): m.predict({"mel": spec.numpy()})
        ms = (time.time() - t0) / 20 * 1000
        report[f"{prec}_{label}"] = {"max_abs_diff_probs": float(np.abs(o["probs"] - ref_p.numpy()).max()),
                                     "max_abs_diff_embedding": float(np.abs(o["embedding"] - ref_e.numpy()).max()),
                                     "ms_per_1s_window": round(ms, 2)}
    report[f"{prec}_size_mb"] = round(size / 1e6, 2)
json.dump(report, open(os.path.join(out, "efficientat_coreml.json"), "w"), indent=1)
print(json.dumps(report, indent=1))
for prec in ("float32", "float16"):
    for label in ("cpuOnly", "all"):
        r = report[f"{prec}_{label}"]
        print(f"RESULT EfficientAT Core ML {prec} {label}: {report[prec + '_size_mb']} MB, {r['ms_per_1s_window']} ms per 1 s window, max |diff| probs {r['max_abs_diff_probs']:.1e}")
