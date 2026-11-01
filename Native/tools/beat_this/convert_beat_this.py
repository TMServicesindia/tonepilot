"""Phase 2, step 1 (CI only): convert the Beat This! small model (MIT, CPJKU) to Core ML, check it
numerically against PyTorch, and write reference fixtures for TonePilot's Swift front-end and
post-processing. Nothing here ships in the app.

Usage: convert_beat_this.py <beat_this repo> <checkpoint.ckpt> <out dir>
Writes:
  out/BeatThisSmall.mlpackage            Core ML model, input spect [1,1500,128], outputs beat/downbeat [1,1500]
  out/fixture/audio.s16                  test signal, 22050 Hz mono int16 (synthetic, licence-free)
  out/fixture/mel.f32                    reference log-mel (frames x 128) from the official LogMelSpect
  out/fixture/beat.f32, downbeat.f32     reference frame logits for the whole piece (official chunking)
  out/fixture/reference.json             beat/downbeat times (official minimal post-processing), hashes
  out/report.json                        Core ML vs PyTorch differences
"""
import hashlib, json, os, sys

import numpy as np
import torch

repo, ckpt, out = sys.argv[1], sys.argv[2], sys.argv[3]
sys.path.insert(0, repo)
from beat_this.inference import load_model, split_predict_aggregate  # noqa: E402
from beat_this.model.postprocessor import Postprocessor  # noqa: E402
from beat_this.preprocessing import LogMelSpect  # noqa: E402

os.makedirs(f"{out}/fixture", exist_ok=True)
sha = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
torch.manual_seed(0)

# --- Test signal: 34 s, 22050 Hz, 100 BPM, 4/4 with accented downbeats, kick/snare/hat + chords ---
sr, bpm, secs = 22050, 100.0, 34.0
n = int(sr * secs); t = np.arange(n) / sr
rng = np.random.default_rng(7)
x = np.zeros(n)
beat = 60.0 / bpm
chords = [[57, 60, 64], [53, 57, 60], [55, 59, 62], [52, 55, 59]]
f = lambda m: 440.0 * 2 ** ((m - 69) / 12)
for i in range(int(secs / beat)):
    s = int(i * beat * sr); e = min(n, s + int(beat * sr)); tt = t[: e - s]
    acc = 1.0 if i % 4 == 0 else 0.6
    if i % 2 == 0:
        x[s:e] += acc * 0.8 * np.sin(2 * np.pi * (50 + 60 * np.exp(-tt * 30)) * tt) * np.exp(-tt * 12)
    else:
        x[s:e] += 0.5 * rng.standard_normal(e - s) * np.exp(-tt * 25)
    for k in range(2):
        hs = s + int(k * beat * sr / 2); he = min(n, hs + 1500)
        x[hs:he] += 0.15 * rng.standard_normal(he - hs) * np.exp(-np.arange(he - hs) / sr * 80)
    for m in chords[(i // 4) % 4]:
        x[s:e] += 0.08 * np.sin(2 * np.pi * f(m) * tt) * np.exp(-tt * 2)
x = x / np.max(np.abs(x)) * 0.8
pcm = np.round(x * 32767).astype("<i2"); pcm.tofile(f"{out}/fixture/audio.s16")
signal = torch.tensor(pcm.astype(np.float32) / 32767.0)

# --- Reference (official code) ---
model = load_model(ckpt, "cpu")
mel = LogMelSpect()(signal)                                     # (frames, 128)
mel.numpy().astype("<f4").tofile(f"{out}/fixture/mel.f32")
with torch.inference_mode():
    pred = split_predict_aggregate(mel, chunk_size=1500, border_size=6, overlap_mode="keep_first", model=model)
b_ref, d_ref = pred["beat"].float(), pred["downbeat"].float()
b_ref.numpy().astype("<f4").tofile(f"{out}/fixture/beat.f32")
d_ref.numpy().astype("<f4").tofile(f"{out}/fixture/downbeat.f32")
beats, downbeats = Postprocessor("minimal")(b_ref, d_ref)

# --- Core ML conversion (fixed chunk 1500 x 128, float32) ---
class Wrap(torch.nn.Module):
    def __init__(self, m): super().__init__(); self.m = m
    def forward(self, spect):
        o = self.m(spect); return o["beat"], o["downbeat"]

import coremltools as ct  # noqa: E402
w = Wrap(model).eval()
example = mel[:1500].unsqueeze(0)
with torch.inference_mode():
    traced = torch.jit.trace(w, example)
mlmodel = ct.convert(traced, inputs=[ct.TensorType(name="spect", shape=(1, 1500, 128), dtype=np.float32)],
                     outputs=[ct.TensorType(name="beat"), ct.TensorType(name="downbeat")],
                     convert_to="mlprogram", compute_precision=ct.precision.FLOAT32,
                     minimum_deployment_target=ct.target.iOS16)
mlmodel.short_description = "Beat This! small (CPJKU, MIT) — TonePilot Phase 2 evaluation, not shipped"
mlmodel.save(f"{out}/BeatThisSmall.mlpackage")

report = {"checkpoint_sha256": sha(ckpt), "frames": int(mel.shape[0]),
          "hparams": {k: v for k, v in torch.load(ckpt, map_location="cpu", weights_only=True)["hyper_parameters"].items() if isinstance(v, (int, float, str, bool))}}
with torch.inference_mode():
    t_b, t_d = w(example)
for label, units in (("cpuOnly", ct.ComputeUnit.CPU_ONLY), ("all", ct.ComputeUnit.ALL)):
    m = ct.models.MLModel(f"{out}/BeatThisSmall.mlpackage", compute_units=units)
    o = m.predict({"spect": example.numpy()})
    report[f"coreml_{label}_max_abs_diff"] = {"beat": float(np.max(np.abs(o["beat"] - t_b.numpy()))),
                                             "downbeat": float(np.max(np.abs(o["downbeat"] - t_d.numpy())))}
    report[f"coreml_{label}_same_peaks"] = bool(np.array_equal(o["beat"] > 0, t_b.numpy() > 0))
ref = {"sample_rate": sr, "bpm": bpm, "beats": [float(v) for v in beats], "downbeats": [float(v) for v in downbeats],
       "checkpoint": os.path.basename(ckpt), "checkpoint_sha256": report["checkpoint_sha256"],
       "audio_sha256": sha(f"{out}/fixture/audio.s16"), "frames": int(mel.shape[0])}
json.dump(ref, open(f"{out}/fixture/reference.json", "w"), indent=1)
json.dump(report, open(f"{out}/report.json", "w"), indent=1)
print(json.dumps(report, indent=1))
print(f"RESULT reference: {len(beats)} beats, {len(downbeats)} downbeats in {secs:.0f} s (truth {int(secs / beat)} beats at {bpm:.0f} BPM)")
for label in ("cpuOnly", "all"):
    d = report[f"coreml_{label}_max_abs_diff"]
    print(f"RESULT Core ML {label}: max |diff| beat {d['beat']:.2e}, downbeat {d['downbeat']:.2e}; same peaks {report[f'coreml_{label}_same_peaks']}")
ok = max(report["coreml_cpuOnly_max_abs_diff"].values()) <= 1e-3 and report["coreml_cpuOnly_same_peaks"]
sys.exit(0 if ok else 1)
