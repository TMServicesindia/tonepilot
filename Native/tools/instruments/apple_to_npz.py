"""Converts apple_windows JSON into the benchmark's per-model .npz (approach A only; Apple exposes
no embeddings). Usage: apple_to_npz.py <apple.json> <out dir>"""
import json, os, sys
import numpy as np
from common import taxonomy, map_scores

_, I, F, _ = taxonomy()
d = json.load(open(sys.argv[1])); out = sys.argv[2]
labels = d["labels"]; flat = {}; files = []
for i, (f, v) in enumerate(d["clips"].items()):
    sc = np.array(v["scores"], np.float32).reshape(-1, len(labels)) if v["scores"] else np.zeros((1, len(labels)), np.float32)
    st = np.array(v["starts"] or [0.0], np.float32)
    inst, fam, src = map_scores(labels, sc, I, F)
    files.append(f)
    flat.update({f"{i}|starts": st, f"{i}|inst": inst, f"{i}|fam": fam, f"{i}|src": src, f"{i}|emb": np.zeros((len(st), 0), np.float32)})
os.makedirs(out, exist_ok=True)
np.savez_compressed(os.path.join(out, "apple.npz"), files=np.array(files), **flat)
info = d["info"]; info["labels_seen"] = len(labels)
json.dump(info, open(os.path.join(out, "apple.json"), "w"), indent=1)
print("APPLE npz", len(files), "clips; labels seen", len(labels))
