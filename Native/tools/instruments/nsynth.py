"""Adds NSynth (Engel et al., CC BY 4.0, real recorded and synthesised notes) to the benchmark as a
CROSS-DOMAIN source: nsynth-valid → DEV (calibration), nsynth-test → separate TEST. Stratified
subsets per family. Family labels only (NSynth has no exact instrument names in our taxonomy).
Usage: nsynth.py <render dir> <per-family count>   (downloads from download.magenta.tensorflow.org)"""
import json, os, sys, tarfile, urllib.request
from collections import defaultdict
import numpy as np

root, per = sys.argv[1], int(sys.argv[2])
train_per = int(sys.argv[3]) if len(sys.argv) > 3 else 0
FAM = {"bass": "Bass", "brass": "Other", "flute": "Western winds", "guitar": "Other plucked", "keyboard": "Keys",
       "mallet": "Bells", "organ": "Keys", "reed": "Western winds", "string": "Strings", "synth_lead": "Electronic", "vocal": "Other"}
URL = "http://download.magenta.tensorflow.org/datasets/nsynth/nsynth-{}.jsonwav.tar.gz"
meta = json.load(open(os.path.join(root, "clips.json")))
for part, split in (("valid", "dev_nsynth"), ("test", "test_nsynth")):
    path = f"/tmp/nsynth-{part}.tar.gz"
    if not os.path.exists(path):
        urllib.request.urlretrieve(URL.format(part), path)
    xdir = f"/tmp/nsynth-{part}"
    if not os.path.isdir(xdir):
        with tarfile.open(path, "r:gz") as tf:   # one sequential pass (random access into .gz is very slow)
            tf.extractall(xdir, filter="data") if hasattr(tarfile, "data_filter") else tf.extractall(xdir)
    base = next(d for d, _, fs in os.walk(xdir) if "examples.json" in fs)
    ex = json.load(open(os.path.join(base, "examples.json")))
    by = defaultdict(list)
    for k, v in sorted(ex.items()):
        if 36 <= v["pitch"] <= 96:                       # playable keyboard range
            by[v["instrument_family_str"]].append((k, v))
    rng = np.random.default_rng(42); n = 0
    for fam, items in sorted(by.items()):
        # Stratify by instrument so one instrument can't dominate a family.
        rng.shuffle(items); seen = defaultdict(int); pick = []
        for k, v in items:
            if seen[v["instrument_str"]] < max(2, per // 10): pick.append((k, v)); seen[v["instrument_str"]] += 1
            if len(pick) >= per: break
        for k, v in pick:
            src = os.path.join(base, "audio", f"{k}.wav")
            if not os.path.exists(src): continue
            rel = f"nsynth/{part}/{k}.wav"; os.makedirs(os.path.join(root, os.path.dirname(rel)), exist_ok=True)
            open(os.path.join(root, rel), "wb").write(open(src, "rb").read())
            meta["clips"].append({"file": rel, "split": split, "kind": "solo", "variant": "original",
                                  "events": [{"key": f"nsynth:{FAM[fam]}", "start": 0.0, "end": 4.0}],
                                  "nsynth": {"family": fam, "source": v["instrument_source_str"], "instrument": v["instrument_str"]}})
            n += 1
    print(f"NSYNTH {part}: {n} notes from {len(by)} families")

# TRAIN (optional): stream nsynth-train (~22 GB, too big for runner disk) and keep a stratified sample
# chosen from file names: <family>_<source>_<nnn>-<pitch>-<velocity>.wav. Separate instruments from valid/test.
if train_per:
    import re
    quota = defaultdict(int); per_inst = defaultdict(int); n = 0
    with urllib.request.urlopen(URL.format("train")) as resp, tarfile.open(fileobj=resp, mode="r|gz") as tf:
        for m in tf:
            g = re.search(r"audio/(([a-z_]+?)_(acoustic|electronic|synthetic)_(\d+))-(\d+)-(\d+)\.wav$", m.name)
            if not g: continue
            inst, fam, src, pitch = g.group(1), g.group(2), g.group(3), int(g.group(5))
            if fam not in FAM or not 36 <= pitch <= 96 or quota[fam] >= train_per or per_inst[inst] >= 4: continue
            data = tf.extractfile(m).read()
            rel = f"nsynth/train/{os.path.basename(m.name)}"; os.makedirs(os.path.join(root, "nsynth/train"), exist_ok=True)
            open(os.path.join(root, rel), "wb").write(data)
            meta["clips"].append({"file": rel, "split": "train_nsynth", "kind": "solo", "variant": "original",
                                  "events": [{"key": f"nsynth:{FAM[fam]}", "start": 0.0, "end": 4.0}],
                                  "nsynth": {"family": fam, "source": src, "instrument": inst}})
            quota[fam] += 1; per_inst[inst] += 1; n += 1
            if all(quota[f] >= train_per for f in FAM if f != "synth_lead") and quota["synth_lead"] >= min(train_per, 50):
                break
    print(f"NSYNTH train (streamed): {n} notes, per family {dict(quota)}")
json.dump(meta, open(os.path.join(root, "clips.json"), "w"), indent=1)
