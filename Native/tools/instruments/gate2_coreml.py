"""Gate 2 (research only, macOS CI): EfficientAT mn10_as → Core ML, optimised and validated.

Variants: fp32 (reference), fp16, int8 weight quantisation, 6-bit palettisation (from fp16).
Compute units: CPU only, CPU + Neural Engine, all. Batch sizes 1, 8, 16.
Numerical suite vs PyTorch fp32 on real benchmark windows (clean, reverb, compressed, layered,
silence, -40 dB) — max/mean/RMS error, embedding cosine, top-1/top-5 agreement, and agreement of
instrument-family decisions through a head trained on the train bank.
Latency: cold load+first prediction, warm median/p90/p95, throughput; full-song estimates (Mac).
Also writes the mel front-end fixture for the Swift implementation.
All numbers are MAC CI measurements or estimates, never iPhone results.
Usage: gate2_coreml.py <EfficientAT repo> <iset dir> <out dir>"""
import json, os, re, resource, sys, time
import numpy as np
import torch

repo, iset, out = sys.argv[1], sys.argv[2], sys.argv[3]
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
from common import read_wav, resample, taxonomy, load_clips  # noqa: E402
sys.path.insert(0, repo); os.chdir(repo)
from models.mn.model import get_model  # noqa: E402
from models.preprocess import AugmentMelSTFT  # noqa: E402
from helpers.utils import NAME_TO_WIDTH  # noqa: E402
import coremltools as ct  # noqa: E402
import coremltools.optimize as cto  # noqa: E402

os.makedirs(out, exist_ok=True)
SR, WIN = 32000, 32000
name = "mn10_as"
model = get_model(width_mult=NAME_TO_WIDTH(name), pretrained_name=name).eval()
mel = AugmentMelSTFT(n_mels=128, sr=SR, win_length=800, hopsize=320).eval()
rss = lambda: resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / (1024 * 1024)  # macOS: bytes → MB

class Net(torch.nn.Module):
    def __init__(self, m): super().__init__(); self.m = m
    def forward(self, x):
        logits, feats = self.m(x)
        return torch.sigmoid(logits), feats.reshape(x.shape[0], -1)
net = Net(model).eval()

def mels(waves):
    with torch.no_grad():
        return mel(torch.from_numpy(np.stack(waves).astype(np.float32))).unsqueeze(1).numpy()

# ---------- 1. Swift front-end fixture ----------
t = np.arange(int(2.5 * SR)) / SR
fx = (0.3 * np.sin(2 * np.pi * 220 * t) + 0.2 * np.sin(2 * np.pi * 660 * t) * np.exp(-t) + 0.05 * np.random.default_rng(3).standard_normal(len(t))).astype(np.float32)
os.makedirs(f"{out}/fixture", exist_ok=True)
fx.astype("<f4").tofile(f"{out}/fixture/audio.f32")
with torch.no_grad():
    fm = mel(torch.from_numpy(fx)[None]).numpy()[0]          # [128, frames]
fm.astype("<f4").tofile(f"{out}/fixture/mel.f32")
json.dump({"sample_rate": SR, "n_mels": 128, "frames": int(fm.shape[1]), "layout": "mel-major [128][frames]",
           "n_fft": 1024, "win_length": 800, "hop": 320, "window": "hann periodic=False, centred in n_fft",
           "preemphasis": [-0.97, 1], "fmin": 0, "fmax": 15000, "mel": "kaldi get_mel_banks + zero column", "log": "ln(x+1e-5)", "norm": "(x+4.5)/5"},
          open(f"{out}/fixture/meta.json", "w"), indent=1)

# ---------- 2. Validation windows from the benchmark clips ----------
clips = load_clips(iset)["clips"]; _, INSTR, FAMS, FAM_OF = taxonomy()
keys = json.load(open(os.path.join(here, "taxonomy.json")))["keys"]
def first_window(path):
    x, sr = read_wav(os.path.join(iset, path)); x = resample(x, sr, SR)
    return np.pad(x, (0, max(0, WIN - len(x))))[:WIN]
val, val_labels, val_kind = [], [], []
for c in clips:
    if c["split"] == "test" and c["kind"] == "solo" and c["file"].endswith("_0.wav") and c["variant"] in ("original", "reverb", "compressed"):
        val.append(first_window(c["file"])); val_labels.append(keys[c["events"][0]["key"]]["family"]); val_kind.append(c["variant"])
    if c["split"] == "test" and c["kind"] == "layered" and re.search(r"track_[0-7]\.wav$", c["file"]):
        x, sr = read_wav(os.path.join(iset, c["file"])); x = resample(x, sr, SR)
        for s in (2, 10, 18):
            val.append(x[s * SR:(s + 1) * SR]); val_labels.append(None); val_kind.append("layered")
val += [np.zeros(WIN, np.float32), (0.01 * np.random.default_rng(1).standard_normal(WIN)).astype(np.float32)]
val_labels += [None, None]; val_kind += ["silence", "minus40dB"]
VAL = mels(val)                                               # [N,1,128,T]
with torch.no_grad():
    ref_p, ref_e = [v.numpy() for v in net(torch.from_numpy(VAL))]

# Family head trained on TRAIN-bank embeddings (torch fp32) — used only to compare decisions.
from sklearn.linear_model import LogisticRegression
tr_w, tr_y = [], []
for c in clips:
    if c["split"] == "train" and c["kind"] == "solo" and c["variant"] == "original":
        tr_w.append(first_window(c["file"])); tr_y.append(keys[c["events"][0]["key"]]["family"])
with torch.no_grad():
    _, tr_e = net(torch.from_numpy(mels(tr_w)))
head = LogisticRegression(max_iter=3000).fit(tr_e.numpy(), tr_y)
ref_fam = head.predict(ref_e)

# ---------- 3. Variants ----------
example = torch.from_numpy(VAL[:1])
with torch.no_grad():
    traced = torch.jit.trace(net, example)
T = VAL.shape[3]
def convert(prec, flexible):
    shape = (ct.RangeDim(1, 32, default=1), 1, 128, T) if flexible else (1, 1, 128, T)
    return ct.convert(traced, inputs=[ct.TensorType(name="mel", shape=shape, dtype=np.float32)],
                      outputs=[ct.TensorType(name="probs"), ct.TensorType(name="embedding")], convert_to="mlprogram",
                      compute_precision=ct.precision.FLOAT32 if prec == "fp32" else ct.precision.FLOAT16,
                      minimum_deployment_target=ct.target.iOS16)
report = {"model": name, "params": int(sum(p.numel() for p in model.parameters())), "input": f"mel [batch,1,128,{T}] for 1 s at 32 kHz",
          "validation_windows": len(val), "validation_kinds": {k: val_kind.count(k) for k in sorted(set(val_kind))},
          "label": "Mac CI (macos-15 runner) measurements; NOT iPhone", "variants": {}}
flexible = True
t0 = time.time()
try:
    base32 = convert("fp32", True); base16 = convert("fp16", True)
except Exception as e:
    print("flexible batch failed, falling back to batch 1:", e); flexible = False
    base32 = convert("fp32", False); base16 = convert("fp16", False)
report["flexible_batch"] = flexible; report["convert_s"] = round(time.time() - t0, 1)
variants = {"fp32": base32, "fp16": base16}
try:
    variants["int8-weights"] = cto.coreml.linear_quantize_weights(base16, config=cto.coreml.OptimizationConfig(
        global_config=cto.coreml.OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8")))
except Exception as e:
    report["int8_error"] = str(e)[:300]
try:
    variants["palettized-6bit"] = cto.coreml.palettize_weights(base16, config=cto.coreml.OptimizationConfig(
        global_config=cto.coreml.OpPalettizerConfig(mode="kmeans", nbits=6)))
except Exception as e:
    report["palettize_error"] = str(e)[:300]

UNITS = {"cpuOnly": ct.ComputeUnit.CPU_ONLY, "cpuAndNE": ct.ComputeUnit.CPU_AND_NE, "all": ct.ComputeUnit.ALL}
def pct(v, p): return float(np.percentile(v, p))
for vname, mlm in variants.items():
    path = f"{out}/EfficientAT_{name}_{vname}.mlpackage"; mlm.save(path)
    size = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(path) for f in fs)
    entry = {"size_mb": round(size / 1e6, 2), "units": {}}
    for uname, unit in UNITS.items():
        r0 = rss(); t0 = time.time()
        m = ct.models.MLModel(path, compute_units=unit)
        first = m.predict({"mel": VAL[:1]}); cold = time.time() - t0
        # Numerics over all validation windows (batch 1 to be identical across variants).
        P, E = [], []
        for i in range(len(VAL)):
            o = m.predict({"mel": VAL[i:i + 1]}); P.append(o["probs"][0]); E.append(o["embedding"][0])
        P, E = np.array(P), np.array(E)
        d = np.abs(P - ref_p)
        cos = (E * ref_e).sum(1) / (np.linalg.norm(E, axis=1) * np.linalg.norm(ref_e, axis=1) + 1e-12)
        top1 = float(np.mean(P.argmax(1) == ref_p.argmax(1)))
        top5 = float(np.mean([len(set(np.argsort(-a)[:5]) & set(np.argsort(-b)[:5])) / 5 for a, b in zip(P, ref_p)]))
        fam_agree = float(np.mean(head.predict(E) == ref_fam))
        # Latency.
        warm = []
        for _ in range(60):
            t1 = time.perf_counter(); m.predict({"mel": VAL[:1]}); warm.append((time.perf_counter() - t1) * 1000)
        warm = warm[10:]
        thr = {}
        if flexible:
            for b in (8, 16):
                xb = np.repeat(VAL[:1], b, axis=0); ts = []
                for _ in range(15):
                    t1 = time.perf_counter(); m.predict({"mel": xb}); ts.append((time.perf_counter() - t1) * 1000)
                thr[f"batch{b}_ms_per_window"] = round(float(np.median(ts[3:])) / b, 3)
        per_win = min([float(np.median(warm))] + list(thr.values()))
        entry["units"][uname] = {
            "cold_load_and_first_ms": round(cold * 1000, 1), "warm_ms_median": round(pct(warm, 50), 3), "warm_ms_p90": round(pct(warm, 90), 3),
            "warm_ms_p95": round(pct(warm, 95), 3), **thr, "windows_per_s": round(1000 / per_win, 1),
            "full_song_s_estimate_hop0.5": {f"{mn}min": round((mn * 60 * 2) * per_win / 1000, 2) for mn in (1, 3, 4, 5)},
            "max_abs_diff_probs": float(d.max()), "mean_abs_diff_probs": float(d.mean()), "rmse_probs": float(np.sqrt((d ** 2).mean())),
            "embedding_cosine_mean": float(cos.mean()), "embedding_cosine_min": float(cos.min()),
            "top1_agreement": top1, "top5_overlap": top5, "family_decision_agreement": fam_agree,
            "process_peak_rss_mb": round(rss(), 1), "rss_growth_mb": round(rss() - r0, 1)}
        print("GATE2", vname, uname, json.dumps(entry["units"][uname]))
    report["variants"][vname] = entry

json.dump(report, open(f"{out}/COREML_DEPLOYMENT_RESULTS.json", "w"), indent=1)

# ---------- 4. Markdown ----------
L = ["# Core ML deployment — Gate 2 results (EfficientAT mn10_as)", "",
     "**All timings are MAC CI measurements (GitHub macos-15 runner) or estimates from them — NOT iPhone results.**",
     f"Validation windows: {len(val)} ({report['validation_kinds']}). Reference: PyTorch fp32. Family decisions via a logistic head trained on the FluidR3 train bank.", "",
     "| Variant | Size MB | Units | Cold load+1st (ms) | Warm median / p90 / p95 (ms) | Best ms/window | 4-min song est. (s) | Max abs diff | Emb. cosine min | Top-1 agree | Family agree |",
     "|---|---|---|---|---|---|---|---|---|---|---|"]
for vname, e in report["variants"].items():
    for u, r in e["units"].items():
        best = min([r["warm_ms_median"]] + [v for k, v in r.items() if k.startswith("batch")])
        L.append(f"| {vname} | {e['size_mb']} | {u} | {r['cold_load_and_first_ms']} | {r['warm_ms_median']} / {r['warm_ms_p90']} / {r['warm_ms_p95']} | {best:.2f} | "
                 f"{r['full_song_s_estimate_hop0.5']['4min']} | {r['max_abs_diff_probs']:.1e} | {r['embedding_cosine_min']:.5f} | {100*r['top1_agreement']:.1f}% | {100*r['family_decision_agreement']:.1f}% |")
for k in ("int8_error", "palettize_error"):
    if k in report: L.append(f"\n- {k}: {report[k]}")
L.append(f"\nFlexible batch: {flexible}. Params: {report['params']}. Front-end fixture written for the Swift mel implementation.")
open(f"{out}/COREML_DEPLOYMENT_REPORT.md", "w").write("\n".join(L) + "\n")
print("\n".join(L))
