"""T1 (tone recreation research): does a learned-embedding similarity find the right tone across
sound sources better than hand features? Uses the dump from ToneTableDump.swift:
  table.json   — every TonePilot melodic tone playing a standard phrase in 3 registers
  targets.json — bench lead/backing stems (with leakage) rendered from one or more GM banks
For each target, every library tone is scored by cosine similarity (best register), and the
ranking is judged by the target's true GM program ("exact") and TonePilot family ("family").
DEV banks only unless a sealed bank is explicitly passed. Research only (CI / local).
Usage: tone_t1.py <dump dir> <out.md> <method,...> [--eat <EfficientAT repo>]
Methods: mfcc | efficientat | panns10 | yamnet | clap, each optionally with "+harm" (harmonic-only
re-synthesis of the part from its true notes, both sides) or "+harmx" (targets masked with the notes
TonePilot's melody extractor produces, as in the app) and/or "+lda" (E-5): a Linear
Discriminant projection learned on train.json (training banks, labelled by family) plus the library
table, so variation between sound sources of the same family is suppressed before the cosine."""
import json, os, sys, time
from collections import defaultdict
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import read_wav, resample, windows


def harmonic_only(x, sr, notes, width=0.03, max_harm=30):
    """Keeps only the STFT bins at each sounding note's harmonics (k·f0 ± 3%), then inverts:
    a cleaned copy of one part from a leaky stem (notes = [[start, dur, midi], ...]). Applied the same
    way to targets and candidates."""
    import librosa
    n_fft, hop = 2048, 512
    S = librosa.stft(x, n_fft=n_fft, hop_length=hop)
    freqs = librosa.fft_frequencies(sr=sr, n_fft=n_fft)
    mask = np.zeros(S.shape, np.float32)
    times = librosa.frames_to_time(np.arange(S.shape[1]), sr=sr, hop_length=hop)
    for start, dur, midi in notes:
        f0 = 440.0 * 2 ** ((midi - 69) / 12)
        cols = np.where((times >= start) & (times <= start + dur + 0.15))[0]
        if not len(cols):
            continue
        for k in range(1, max_harm + 1):
            f = k * f0
            if f > sr / 2 * 0.95:
                break
            rows = np.where(np.abs(freqs - f) <= max(width * f, 1.5 * sr / n_fft))[0]
            mask[np.ix_(rows, cols)] = 1.0
    return librosa.istft(S * mask, hop_length=hop, length=len(x)).astype(np.float32)


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


_CACHE = {}
EMBEDDERS = {}


# ---- Device-parity path: the Swift EfficientATFrontEnd reproduced in numpy, with the harmonic mask
# applied to the power spectrum (exactly what the app would run), then the model on the mel. ----
_SR, _NFFT, _WIN, _HOP, _NMELS = 32000, 1024, 800, 320, 128


def _mel_bank():
    def mel(f): return 1127.0 * np.log(1 + f / 700.0)
    bins, width = _NFFT // 2, _SR / _NFFT
    lo, hi = mel(0.0), mel(15000.0); delta = (hi - lo) / (_NMELS + 1)
    m = mel(width * np.arange(bins))
    bank = np.zeros((_NMELS, bins))
    for b in range(_NMELS):
        left = lo + b * delta; center = left + delta; right = center + delta
        bank[b] = np.maximum(0, np.minimum((m - left) / (center - left), (right - m) / (right - center)))
    return bank


_BANK = None


def device_logmel(x, notes=None, width=0.03, max_harm=30):
    """Swift EfficientATFrontEnd.logMel in numpy (+ optional harmonic power mask)."""
    global _BANK
    if _BANK is None:
        _BANK = _mel_bank()
    y = x[1:] - 0.97 * x[:-1]
    pad = _NFFT // 2
    p = np.concatenate([y[1:pad + 1][::-1], y, y[-pad - 1:-1][::-1]])
    frames = 1 + len(y) // _HOP
    w = np.zeros(_NFFT); off = (_NFFT - _WIN) // 2
    w[off:off + _WIN] = 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(_WIN) / (_WIN - 1))
    idx = np.arange(_NFFT)[None, :] + _HOP * np.arange(frames)[:, None]
    X = np.fft.rfft(p[idx] * w, axis=1)[:, : _NFFT // 2]
    power = (X.real ** 2 + X.imag ** 2)
    if notes:
        binhz = _SR / _NFFT
        freqs = np.arange(_NFFT // 2) * binhz
        times = np.arange(frames) * _HOP / _SR
        keep = np.zeros_like(power, dtype=bool)
        for start, dur, midi in notes:
            f0 = 440.0 * 2 ** ((midi - 69) / 12)
            rows = np.where((times >= start) & (times <= start + dur + 0.15))[0]
            if not len(rows):
                continue
            for k in range(1, max_harm + 1):
                f = k * f0
                if f > 15000:
                    break
                cols = np.abs(freqs - f) <= max(width * f, 1.5 * binhz)
                keep[np.ix_(rows, np.where(cols)[0])] = True
        power = np.where(keep, power, 0.0)
    melp = power @ _BANK.T
    return ((np.log(melp + 1e-5) + 4.5) / 5).T.astype(np.float32)   # [128, frames]


def efficientat_device_embedder(eat):
    import embed as E
    import torch
    model = E.EfficientAT(eat)
    def f(x, sr, notes=None):
        y = resample(x, sr, _SR)
        if len(y) < _SR:
            y = np.pad(y, (0, _SR - len(y)))
        mel = device_logmel(y, notes)
        n = mel.shape[1]
        starts = list(range(0, max(1, n - 101 + 1), 50)) or [0]
        wins = []
        for s0 in starts:
            w = mel[:, s0:s0 + 101]
            if w.shape[1] < 101:
                w = np.pad(w, ((0, 0), (0, 101 - w.shape[1])), constant_values=float((np.log(1e-5) + 4.5) / 5))
            wins.append(w)
        with torch.no_grad():
            _, feats = model.m(torch.from_numpy(np.stack(wins))[:, None])
        return feats.reshape(len(wins), -1).numpy().mean(0)
    return f


def evaluate(dump, method, embed_fn):
    table = json.load(open(os.path.join(dump, "table.json")))
    targets = json.load(open(os.path.join(dump, "targets.json")))
    base = method.split("+")[0]
    device = "+harmp" in method        # device-parity: mask in the Swift front-end's power domain
    harmx = "+harmx" in method or "+harmpx" in method   # targets masked with the app's EXTRACTED notes
    harm = harmx or "+harm" in method
    key = base + ("+harmpx" if device and harmx else "+harmp" if device else "+harmx" if harmx else "+harm" if harm else "")
    t0 = time.time()
    def emb(r):
        x, sr = read_wav(os.path.join(dump, r["file"]))
        notes = r.get("notes_extracted") if (harmx and "notes_extracted" in r) else r.get("notes")
        if device:
            return embed_fn(x, sr, notes)
        if harm and notes:
            x = harmonic_only(x, sr, notes)
        return embed_fn(x, sr)
    if key not in _CACHE:
        T0 = np.stack([emb(r) for r in table])
        G0 = np.stack([emb(r) for r in targets])
        tp = os.path.join(dump, "train.json")
        train = json.load(open(tp)) if os.path.exists(tp) else []
        R0 = np.stack([emb(r) for r in train]) if train else None
        _CACHE[key] = (T0, G0, R0, train)
    T, G, R, train = [x.copy() if isinstance(x, np.ndarray) else x for x in _CACHE[key]]
    secs = time.time() - t0
    if base == "mfcc":   # z-score each dimension on the library (hand features have mixed scales)
        mu, sd = T.mean(0), T.std(0) + 1e-6
        T, G = (T - mu) / sd, (G - mu) / sd
        R = (R - mu) / sd if R is not None else None
    if method.endswith("+lda"):
        from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
        if R is None:
            raise SystemExit("+lda needs train.json (TP_TONE_TRAIN_BANKS)")
        X = np.concatenate([R, T]); y = [r["family"] for r in train] + [r["family"] for r in table]
        lda = LinearDiscriminantAnalysis(solver="eigen", shrinkage="auto").fit(X, y)
        T, G = lda.transform(T), lda.transform(G)
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


def export_tables(dump, eat, out_dir):
    """The app's tone tables (PerceptualToneSearch.ToneTable JSON): every library tone × register,
    embedded with the device-parity path: 'harmonic' (masked with the tone's own phrase notes; used for
    lead / melody parts) and 'plain' (unmasked; used for backing / pads)."""
    table = json.load(open(os.path.join(dump, "table.json")))
    f = efficientat_device_embedder(eat)
    os.makedirs(out_dir, exist_ok=True)
    for name, masked in (("harmonic", True), ("plain", False)):
        entries = []
        for r in table:
            x, sr = read_wav(os.path.join(dump, r["file"]))
            e = f(x, sr, r["notes"] if masked else None)
            entries.append({"patch": r["patch"], "register": r["register"], "embedding": [round(float(v), 5) for v in e]})
        doc = {"version": 1, "model": f"efficientat_mn10_as/device-frontend/{name}", "embeddingDim": len(entries[0]["embedding"]), "entries": entries}
        json.dump(doc, open(os.path.join(out_dir, f"tone_table_{name}.json"), "w"), separators=(",", ":"))
        print(f"EXPORT tone_table_{name}.json: {len(entries)} entries, dim {doc['embeddingDim']}", flush=True)


def main():
    if "--export-tables" in sys.argv:
        eat = sys.argv[sys.argv.index("--eat") + 1]
        export_tables(sys.argv[1], eat, sys.argv[sys.argv.index("--export-tables") + 1])
        return
    dump, out_md, methods = sys.argv[1], sys.argv[2], sys.argv[3].split(",")
    eat = sys.argv[sys.argv.index("--eat") + 1] if "--eat" in sys.argv else None
    lines = ["# T1: tone search by embedding similarity (research; rendered GM banks, NOT real songs)", "",
             "| Method | Target bank | Part | Top-1 exact | Top-1 family | Top-3 family |", "|---|---|---|---|---|---|"]
    notes, detail = [], {}
    for m in methods:
        base = m.split("+")[0]
        ek = base + ("@device" if "+harmp" in m else "")
        if ek not in EMBEDDERS:
            if "+harmp" in m:
                assert base == "efficientat", "device-parity path is implemented for EfficientAT"
                EMBEDDERS[ek] = efficientat_device_embedder(eat)
            else:
                EMBEDDERS[ek] = mfcc_embed if base == "mfcc" else model_embedder(base, eat)
        fn = EMBEDDERS[ek]
        rows, secs = evaluate(dump, m, fn)
        L, note = summarise(m, rows, secs)
        lines += L; notes.append(note); detail[m] = rows
        print("\n".join(L), flush=True)
    lines += ["", *notes, "", "Per-target top-1 (first method rows in the JSON)."]
    open(out_md, "w").write("\n".join(lines) + "\n")
    json.dump(detail, open(out_md.replace(".md", ".json"), "w"), indent=1)


if __name__ == "__main__":
    main()
