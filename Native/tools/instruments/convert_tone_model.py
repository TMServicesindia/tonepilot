"""App nearest-sound model (macOS CI): EfficientAT mn10_as → Core ML fp16 with the input the app
actually sends, [1, 1, 128, 101] (the Swift front-end makes 1 + n/hop = 101 frames per 1 s window,
the same windows the tone tables and the sealed tone test used). The Gate 2 conversion was traced on
100-frame windows, so Core ML rejected the app's 101-frame windows (full build run 41415425679).

Same tool versions and conversion settings as Gate 2 (coremltools 8.2, mlprogram, fp16, iOS 16).
Checks against PyTorch fp32 on 101-frame windows from the device front-end (numpy copy of the Swift
code): the Gate 2 fixture window, synthetic tones (plain and harmonic-masked) and silence; per window
embedding cosine and whether the nearest tone in the bundled tone tables stays the same.
Mac CI measurements only. Usage: convert_tone_model.py <EfficientAT repo> <tone table dir> <out dir>"""
import json, os, sys, time
import numpy as np
import torch

repo, tables, out = sys.argv[1], sys.argv[2], sys.argv[3]
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
from tone_t1 import device_logmel  # noqa: E402  (parity with Swift 2.2e-5)
fixture = os.path.join(here, "../../../Packages/TonePilotCore/Tests/TonePilotCoreTests/Fixtures/instruments/efficientat")
sys.path.insert(0, repo); os.chdir(repo)
from models.mn.model import get_model  # noqa: E402
from helpers.utils import NAME_TO_WIDTH  # noqa: E402
import coremltools as ct  # noqa: E402

SR, T = 32000, 101
model = get_model(width_mult=NAME_TO_WIDTH("mn10_as"), pretrained_name="mn10_as").eval()


class Net(torch.nn.Module):
    def __init__(self, m): super().__init__(); self.m = m
    def forward(self, x):
        logits, feats = self.m(x)
        return torch.sigmoid(logits), feats.reshape(x.shape[0], -1)


net = Net(model).eval()

# ---- validation windows: [128, 101] each, from the device front-end ----
PAD = float((np.log(1e-5) + 4.5) / 5)
def win(mel):
    w = np.full((128, T), PAD, np.float32); n = min(T, mel.shape[1]); w[:, :n] = mel[:, :n]; return w
t = np.arange(SR) / SR
rng = np.random.default_rng(7)
def tone(f0, kind):
    if kind == "sine": x = np.sin(2 * np.pi * f0 * t)
    elif kind == "saw": x = sum(np.sin(2 * np.pi * k * f0 * t) / k for k in range(1, 30) if k * f0 < 15000)
    elif kind == "square": x = sum(np.sin(2 * np.pi * k * f0 * t) / k for k in range(1, 30, 2) if k * f0 < 15000)
    elif kind == "pluck": x = sum(np.sin(2 * np.pi * k * f0 * t) * np.exp(-t * 3 * k) / k for k in range(1, 20) if k * f0 < 15000)
    else: x = rng.standard_normal(SR)
    return (0.3 * x / (np.abs(x).max() + 1e-9)).astype(np.float32)
cases = []
audio = np.fromfile(os.path.join(fixture, "audio.f32"), dtype="<f4")
cases.append(("fixture 0-1 s", win(device_logmel(audio))))
cases.append(("fixture 1-2 s", win(device_logmel(audio[SR:2 * SR]))))
for kind in ("sine", "saw", "square", "pluck"):
    for midi in (48, 62, 74, 86):
        f0 = 440 * 2 ** ((midi - 69) / 12); x = tone(f0, kind)
        x = x + 0.05 * tone(0, "noise")                         # some leakage
        cases.append((f"{kind} {midi}", win(device_logmel(x))))
        cases.append((f"{kind} {midi} masked", win(device_logmel(x, notes=[[0.05, 0.8, midi]]))))
cases.append(("noise", win(device_logmel(tone(0, "noise")))))
cases.append(("silence", win(device_logmel(np.zeros(SR, np.float32)))))
X = np.stack([c[1] for c in cases])[:, None]                    # [N,1,128,101]
with torch.no_grad():
    ref_p, ref_e = [v.numpy() for v in net(torch.from_numpy(X))]
    traced = torch.jit.trace(net, torch.from_numpy(X[:1]))

ml = ct.convert(traced, inputs=[ct.TensorType(name="mel", shape=(1, 1, 128, T), dtype=np.float32)],
                outputs=[ct.TensorType(name="probs"), ct.TensorType(name="embedding")], convert_to="mlprogram",
                compute_precision=ct.precision.FLOAT16, minimum_deployment_target=ct.target.iOS16)
ml.short_description = "EfficientAT mn10_as (fschmid56/EfficientAT, MIT), fp16, input mel [1,1,128,101] = 1 s at 32 kHz"
os.makedirs(out, exist_ok=True)
path = os.path.join(out, "EfficientAT_mn10_as_fp16.mlpackage"); ml.save(path)
size = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(path) for f in fs)

tabs = {k: json.load(open(os.path.join(tables, f"tone_table_{k}.json"))) for k in ("harmonic", "plain")}
def nearest(e, tab):
    best = {}
    en = np.linalg.norm(e)
    for r in tab["entries"]:
        v = np.asarray(r["embedding"], np.float64); c = float(e @ v / (en * np.linalg.norm(v) + 1e-12))
        if c > best.get(r["patch"], -2): best[r["patch"]] = c
    return max(best, key=best.get)

report = {"input_shape": [1, 1, 128, T], "size_mb": round(size / 1e6, 2), "windows": len(cases), "units": {}}
ok = True
for label, units in (("cpuOnly", ct.ComputeUnit.CPU_ONLY), ("all", ct.ComputeUnit.ALL)):
    m = ct.models.MLModel(path, compute_units=units)
    cos, diffp, agree, rows = [], [], {"harmonic": 0, "plain": 0}, []
    for i, (name, w) in enumerate(cases):
        o = m.predict({"mel": X[i:i + 1]})
        e = np.asarray(o["embedding"], np.float64).reshape(-1); r = ref_e[i].astype(np.float64)
        c = float(e @ r / (np.linalg.norm(e) * np.linalg.norm(r) + 1e-12)) if np.linalg.norm(r) > 0 else 1.0
        cos.append(c); diffp.append(float(np.abs(np.asarray(o["probs"]).reshape(-1) - ref_p[i]).max()))
        same = {k: nearest(e, tab) == nearest(r, tab) for k, tab in tabs.items()}
        for k in agree: agree[k] += same[k]
        rows.append({"window": name, "cosine": round(c, 6), "same_nearest_tone": same})
    t0 = time.time()
    for _ in range(20): m.predict({"mel": X[:1]})
    ms = (time.time() - t0) / 20 * 1000
    u = {"min_cosine": round(min(cos), 6), "mean_cosine": round(float(np.mean(cos)), 6), "max_abs_diff_probs": round(max(diffp), 5),
         "nearest_tone_agreement": {k: f"{v}/{len(cases)}" for k, v in agree.items()}, "ms_per_window": round(ms, 2), "rows": rows}
    report["units"][label] = u
    print(f"RESULT {label}: embedding cosine min {u['min_cosine']:.5f} mean {u['mean_cosine']:.5f} vs PyTorch fp32 over {len(cases)} windows; "
          f"same nearest tone {agree['harmonic']}/{len(cases)} (harmonic table), {agree['plain']}/{len(cases)} (plain table); "
          f"max |diff| probs {u['max_abs_diff_probs']:.1e}; {ms:.1f} ms per window; {report['size_mb']} MB")
    ok &= min(cos) >= 0.998 and min(agree.values()) >= len(cases) - 2
json.dump(report, open(os.path.join(out, "tone_model_coreml.json"), "w"), indent=1)
if not ok:
    print("FAIL fp16 model doesn't reproduce PyTorch closely enough (cosine < 0.998 or nearest tone changed on > 2 windows)")
    sys.exit(1)
