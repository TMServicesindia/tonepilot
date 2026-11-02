"""T3 (tone recreation): judges the tone fit on the DEV tone bench with models the fit never used.
Input: the dump from ToneFitBench.swift (fits.json + clips/<id>_{target,plain,fitted}.wav).

Reference: the part ALONE ("clean", no leakage) — what the part really sounds like; the app only ever
has the leaky stem ("target"), so a fit that copies leakage is caught. Scores against the stem are
reported too.
The app keeps a fit only when its nearest-sound model (EfficientAT, harmonic-masked for melody
parts) hears the fitted tone at least as close to the part as the plain tone; that decision is
reproduced here ("applied"). The verdict comes from independent judges:
  - PANNs CNN10 embedding cosine (another AudioSet model, different architecture and front-end);
  - MFCC mean+std distance (hand features).
Pre-registered gate (written before the first run; TONEPILOT_TONE_RECREATION_PROPOSAL.md T3):
  among parts where a fit was applied, CNN10 hears the fitted tone closer in >= 50 %, and no part is
  worse by more than 0.01 CNN10 cosine. Reported per bank / variant / part, plus "ungated" (every fit
  applied, without the app's check) to show what the check is worth.
Usage: tone_fit_eval.py <dump dir> <out.md> --eat <EfficientAT repo>"""
import json, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import read_wav, resample  # noqa: E402
from tone_t1 import mfcc_embed, model_embedder, efficientat_device_embedder  # noqa: E402

dump, out_md = sys.argv[1], sys.argv[2]
eat = sys.argv[sys.argv.index("--eat") + 1]
rows = json.load(open(os.path.join(dump, "fits.json")))
cnn = model_embedder("panns10", eat)
eff = efficientat_device_embedder(eat)


def cos(a, b):
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-12))


results, mfccs = [], {}
for r in rows:
    clips = {k: read_wav(os.path.join(dump, "clips", f"{r['id']}_{k}.wav")) for k in ("target", "clean", "plain", "fitted")}
    notes = r["notes_extracted"] if r["part"] != "backing" else None
    e = {k: eff(x, sr, notes) for k, (x, sr) in clips.items()}
    c = {k: cnn(x, sr) for k, (x, sr) in clips.items()}
    m = {k: mfcc_embed(x, sr) for k, (x, sr) in clips.items()}
    # The app's check sees only the stem (with leakage).
    applied = r["fitted"] and cos(e["fitted"], e["target"]) > cos(e["plain"], e["target"])
    results.append(dict(r, applied=applied,
                        eff_plain=cos(e["plain"], e["target"]), eff_fitted=cos(e["fitted"], e["target"]),
                        cnn_plain=cos(c["plain"], c["clean"]), cnn_fitted=cos(c["fitted"], c["clean"]),
                        cnn_plain_stem=cos(c["plain"], c["target"]), cnn_fitted_stem=cos(c["fitted"], c["target"])))
    mfccs[r["id"]] = m
# MFCC: z-score each dimension over every clip, then Euclidean distance.
allm = np.stack([v for d in mfccs.values() for v in d.values()])
mu, sd = allm.mean(0), allm.std(0) + 1e-9
for r in results:
    m = {k: (v - mu) / sd for k, v in mfccs[r["id"]].items()}
    r["mfcc_plain"] = float(np.linalg.norm(m["plain"] - m["clean"]))
    r["mfcc_fitted"] = float(np.linalg.norm(m["fitted"] - m["clean"]))


def summarise(rs, gated=True):
    """CNN10 gain / MFCC change of the tone the app would play (fitted if applied, else plain)."""
    n = len(rs)
    use = [r for r in rs if (r["applied"] if gated else r["fitted"])]
    gains = [r["cnn_fitted"] - r["cnn_plain"] for r in use]
    mg = [r["mfcc_plain"] - r["mfcc_fitted"] for r in use]          # > 0 = closer
    better = sum(g > 0.002 for g in gains); worse = [g for g in gains if g < -0.01]
    return dict(n=n, applied=len(use), better=better, worse=len(worse), worst=min(gains) if gains else 0.0,
                mean_gain=float(np.mean(gains)) if gains else 0.0, mfcc_better=sum(x > 0 for x in mg),
                mean_mfcc=float(np.mean(mg)) if mg else 0.0)


lines = ["# Tone fit (T3) on the DEV tone bench — independent judges", "",
         "Rendered GM audio (DEV banks), not real songs. 'Applied' = the app's nearest-sound check kept the fit.",
         "Judged against the part alone (no leakage). CNN10 gain = cosine(fitted, part) − cosine(plain, part) for the parts where the fit was applied; better = gain > 0.002; worse = gain < −0.01.",
         "", "| Group | Parts | Fit applied | CNN10 better | CNN10 worse (< −0.01) | Worst | Mean CNN10 gain | MFCC closer | Mean MFCC gain |",
         "|---|---|---|---|---|---|---|---|---|"]
groups = {}
for r in results:
    groups.setdefault(f"{r['bank']} · {r['variant']} · {r['part']}", []).append(r)
def row(name, s):
    return (f"| {name} | {s['n']} | {s['applied']} | {s['better']}/{s['applied']} | {s['worse']} | {s['worst']:+.3f} | {s['mean_gain']:+.4f} | "
            f"{s['mfcc_better']}/{s['applied']} | {s['mean_mfcc']:+.3f} |")
for k in sorted(groups):
    lines.append(row(k, summarise(groups[k])))
total = summarise(results); ungated = summarise(results, gated=False)
lines.append(row("**All (as the app plays it)**", total))
lines.append(row("All, ungated (every fit applied)", ungated))
passed = total["applied"] > 0 and total["better"] >= 0.5 * total["applied"] and total["worse"] == 0
lines += ["", f"**Pre-registered gate:** CNN10 better in ≥ 50 % of applied fits and none worse by > 0.01 → "
          f"{'PASS' if passed else 'FAIL'} ({total['better']}/{total['applied']} better, {total['worse']} worse)."]
open(out_md, "w").write("\n".join(lines) + "\n")
json.dump(results, open(out_md.replace(".md", ".json"), "w"), indent=1)
print("\n".join(lines))
print(f"RESULT tone fit gate {'PASS' if passed else 'FAIL'}: CNN10 better {total['better']}/{total['applied']} applied fits, "
      f"{total['worse']} worse (worst {total['worst']:+.3f}); MFCC closer {total['mfcc_better']}/{total['applied']}; "
      f"ungated: better {ungated['better']}/{ungated['applied']}, worse {ungated['worse']}")
