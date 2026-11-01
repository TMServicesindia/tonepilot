"""Processed variants for the instrument benchmark (research only, CI).
Test solo clips get: reverb (studio-like hall), compressed+saturated (film-mix loudness), short (first 1 s).
Train solo clips get reverb and compressed copies (augmentation for the hybrid head).
Usage: variants.py <render dir>   (updates <dir>/clips.json in place)"""
import json, os, sys
import numpy as np
from common import read_wav, write_wav

rng = np.random.default_rng(1234)


def reverb(x, sr, rt60=1.2, wet=0.35):
    n = int(sr * rt60 * 1.2)
    t = np.arange(n) / sr
    ir = rng.standard_normal(n) * np.exp(-6.9 * t / rt60)
    ir[: int(0.02 * sr)] = 0                      # 20 ms pre-delay
    ir /= np.sqrt((ir ** 2).sum())
    y = np.convolve(x, ir)[: len(x)]
    return (1 - wet) * x + wet * y / max(1e-6, np.abs(y).max()) * np.abs(x).max()


def compress(x, sr, thr_db=-24, ratio=5, drive=2.0):
    win = int(0.01 * sr)
    env = np.sqrt(np.convolve(x ** 2, np.ones(win) / win, mode="same") + 1e-9)
    level = 20 * np.log10(env)
    gain_db = np.where(level > thr_db, (thr_db - level) * (1 - 1 / ratio), 0)
    y = x * 10 ** (gain_db / 20)
    return np.tanh(drive * y / max(1e-6, np.abs(y).max()))


def main(root):
    meta = json.load(open(os.path.join(root, "clips.json")))
    out = []
    for c in meta["clips"]:
        c.setdefault("variant", "original")
        out.append(c)
        if c["kind"] != "solo" or c["variant"] != "original":
            continue
        x, sr = read_wav(os.path.join(root, c["file"]))
        kinds = ["reverb", "compressed", "short"] if c["split"] == "test" else ["reverb", "compressed"]
        for v in kinds:
            y = reverb(x, sr) if v == "reverb" else compress(x, sr) if v == "compressed" else x[: int(1.0 * sr)]
            f = c["file"].replace("/solo/", f"/solo_{v}/")
            write_wav(os.path.join(root, f), y, sr)
            d = dict(c); d["file"] = f; d["variant"] = v
            if v == "short":
                d["events"] = [dict(e, end=1.0) for e in c["events"]]
            out.append(d)
    meta["clips"] = out
    json.dump(meta, open(os.path.join(root, "clips.json"), "w"), indent=1)
    from collections import Counter
    print("VARIANTS", Counter((c["split"], c["kind"], c["variant"]) for c in out))


if __name__ == "__main__":
    main(sys.argv[1])
