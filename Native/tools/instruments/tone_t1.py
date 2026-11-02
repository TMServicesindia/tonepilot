"""T1 (tone recreation research): does a learned-embedding similarity find the right tone across
sound sources better than hand features? Uses the dump from ToneTableDump.swift:
  table.json   — every TonePilot melodic tone playing a standard phrase in 3 registers
  targets.json — bench lead/backing stems (with leakage) rendered from one or more GM banks
For each target, every library tone is scored by cosine similarity (best register), and the
ranking is judged by the target's true GM program ("exact") and TonePilot family ("family").
DEV banks only unless a sealed bank is explicitly passed. Research only (CI / local).
Usage: tone_t1.py <dump dir> <out.md> <method,...> [--eat <EfficientAT repo>]
Methods: mfcc | efficientat | panns10 | yamnet | clap"""
import json, os, sys, time
from collections import defaultdict
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import read_wav, resample, windows


def mfcc_embed(x, sr):
    import librosa
    y = resample(x, sr, 22050)
    m = librosa.feature.mfcc(y=y, sr=22050, n_mfcc=20)
    rms = librosa.feature.rms(y=y)[0]
    keep = rms > 0.1 * rms.max() if rms.max() > 0 else np.ones_like(rms, bool)
    m = m[:, keep[: m.shape[1]]] if keep[: m.shape[1]].any() else m
    return np.concatenate([m.mean(1), m.std(1)])


def model_embedder(name, eat):
    import embed as E
    model = {"efficientat": lambda: E.EfficientAT(eat), "panns10": E.PANNsCNN10, "yamnet": E.YAMNet, "clap": E.CLAP}[name]()
    win = 10.0 if name == "clap" else 1.0
    def f(x, sr):
        y = resample(x, sr, model.sr)
        if len(y) < int(win * model.sr):
            y = np.pad(y, (0, int(win * model.sr) - len(y)))
        _, ws = windows(y, model.sr, win, win / 2)
        _, emb = model(ws)
        return np.asarray(emb, np.float32).mean(0)
    return f


def evaluate(dump, method, embed_fn):
    table = json.load(open(os.path.join(dump, "table.json")))
    targets = json.load(open(os.path.join(dump, "targets.json")))
    t0 = time.time()
    T = np.stack([embed_fn(*read_wav(os.path.join(dump, r["file"]))) for r in table])
    G = np.stack([embed_fn(*read_wav(os.path.join(dump, r["file"]))) for r in targets])
    secs = time.time() - t0
    if method == "mfcc":   # z-score each dimension on the library (hand features have mixed scales)
        mu, sd = T.mean(0), T.std(0) + 1e-6
        T, G = (T - mu) / sd, (G - mu) / sd
    T /= np.linalg.norm(T, axis=1, keepdims=True) + 1e-9
    G /= np.linalg.norm(G, axis=1, keepdims=True) + 1e-9
    sims = G @ T.T
    patches = sorted({r["patch"] for r in table})
    meta = {r["patch"]: r for r in table}
    rows = []
    for i, tgt in enumerate(targets):
        best = defaultdict(lambda: -9.0)
        for j, r in enumerate(table):
            best[r["patch"]] = max(best[r["patch"]], float(sims[i, j]))
        ranked = sorted(patches, key=lambda p: -best[p])
        top = [meta[p] for p in ranked[:3]]
        rows.append({"bank": tgt["bank"], "part": tgt["part"], "case": tgt["case"], "truth_family": tgt["family"],
                     "top1": top[0]["name"], "top1_family": top[0]["family"],
                     "exact1": top[0]["soundfont"] and top[0]["program"] == tgt["program"],
                     "family1": top[0]["family"] == tgt["family"],
                     "family3": any(t["family"] == tgt["family"] for t in top)})
    return rows, secs


def summarise(method, rows, secs):
    out = []
    groups = defaultdict(list)
    for r in rows:
        groups[(r["bank"], r["part"])].append(r)
    for (bank, part), g in sorted(groups.items()):
        n = len(g)
        out.append(f"| {method} | {bank} | {part} | {sum(r['exact1'] for r in g)}/{n} | {sum(r['family1'] for r in g)}/{n} | {sum(r['family3'] for r in g)}/{n} |")
    return out, f"{method}: embedding time {secs:.0f} s for all clips"


def main():
    dump, out_md, methods = sys.argv[1], sys.argv[2], sys.argv[3].split(",")
    eat = sys.argv[sys.argv.index("--eat") + 1] if "--eat" in sys.argv else None
    lines = ["# T1: tone search by embedding similarity (research; rendered GM banks, NOT real songs)", "",
             "| Method | Target bank | Part | Top-1 exact | Top-1 family | Top-3 family |", "|---|---|---|---|---|---|"]
    notes, detail = [], {}
    for m in methods:
        fn = mfcc_embed if m == "mfcc" else model_embedder(m, eat)
        rows, secs = evaluate(dump, m, fn)
        L, note = summarise(m, rows, secs)
        lines += L; notes.append(note); detail[m] = rows
        print("\n".join(L), flush=True)
    lines += ["", *notes, "", "Per-target top-1 (first method rows in the JSON)."]
    open(out_md, "w").write("\n".join(lines) + "\n")
    json.dump(detail, open(out_md.replace(".md", ".json"), "w"), indent=1)


if __name__ == "__main__":
    main()
