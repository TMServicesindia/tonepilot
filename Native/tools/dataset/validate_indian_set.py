"""Validates the Indian acceptance-set manifest (docs/benchmark/indian-set/manifest.json).
Usage: validate_indian_set.py <manifest.json> [--self-test]
Every clip needs a source, licence, licence status, audio SHA-256, train/test split and annotations.
A clip whose licence status is not Cleared may be used only for evaluation, never training.
Train and test may not share an audio hash or a source recording ("source_group")."""
import json, re, sys

SPLITS = {"train", "test"}
STATUSES = {"Cleared", "SAFE*", "Personal only", "Rejected", "Unverified"}
CYCLE_STATES = {"confident", "ambiguous", "unknown"}

def check_clip(c):
    e, cid = [], c.get("id", "?")
    for k in ("id", "split", "source", "rights_holder", "licence", "licence_status", "audio", "annotations"):
        if k not in c: e.append(f"{cid}: missing '{k}'")
    if c.get("split") not in SPLITS: e.append(f"{cid}: split must be train or test")
    if c.get("licence_status") not in STATUSES: e.append(f"{cid}: unknown licence status")
    if c.get("licence_status") == "Rejected": e.append(f"{cid}: rejected licence")
    if c.get("split") == "train" and c.get("licence_status") != "Cleared": e.append(f"{cid}: only Cleared clips may be used for training")
    a = c.get("audio", {})
    if not re.fullmatch(r"[0-9a-f]{64}", str(a.get("sha256", ""))): e.append(f"{cid}: audio.sha256 must be 64 hex characters")
    if not isinstance(a.get("duration_s"), (int, float)) or a["duration_s"] <= 0: e.append(f"{cid}: audio.duration_s must be > 0")
    an = c.get("annotations", {})
    if not an.get("annotator"): e.append(f"{cid}: annotations.annotator missing")
    cyc = an.get("cycle", {})
    if cyc.get("state") not in CYCLE_STATES: e.append(f"{cid}: cycle.state must be confident/ambiguous/unknown")
    for key in ("beats", "downbeats"):
        t = an.get(key, [])
        if any(b2 <= b1 for b1, b2 in zip(t, t[1:])): e.append(f"{cid}: {key} not increasing")
    dur = a.get("duration_s", 0) or 0
    for key in ("chords", "accompaniment", "sections"):
        for seg in an.get(key, []):
            if not (0 <= seg.get("start", -1) < seg.get("end", -1) <= dur + 1e-6): e.append(f"{cid}: {key} segment {seg} outside clip")
    return e

def check(m):
    errors, clips = [], m.get("clips", [])
    ids = [c.get("id") for c in clips]
    errors += [f"duplicate id {i}" for i in set(ids) if ids.count(i) > 1]
    for c in clips: errors += check_clip(c)
    def keys(split, f): return {f(c) for c in clips if c.get("split") == split and f(c)}
    for name, f in (("audio hash", lambda c: c.get("audio", {}).get("sha256")), ("source recording", lambda c: c.get("source_group"))):
        for k in keys("train", f) & keys("test", f): errors.append(f"train/test leak: {name} {k} in both splits")
    return errors

def summary(m):
    clips = m.get("clips", [])
    n = len(clips); test = sum(c.get("split") == "test" for c in clips)
    tags = {}
    for c in clips:
        for t in c.get("tags", []): tags[t] = tags.get(t, 0) + 1
    return n, test, tags

def main():
    if "--self-test" in sys.argv:
        ex = json.load(open(sys.argv[1].replace("manifest.json", "clip.example.json")))
        ex["audio"]["sha256"] = "0" * 64
        assert not check({"clips": [ex]}), check({"clips": [ex]})
        bad = dict(ex, split="train", licence_status="SAFE*")
        assert check({"clips": [bad]}), "non-Cleared training clip must fail"
        leak = dict(ex, id="b", split="train", licence_status="Cleared")
        assert any("leak" in x for x in check({"clips": [ex, leak]})), "train/test leak must fail"
        print("self-test passed: example clip valid; uncleared training clip and train/test leak rejected")
        return 0
    m = json.load(open(sys.argv[1]))
    errors = check(m)
    for x in errors: print(f"::error title=Indian set::{x}")
    n, test, tags = summary(m)
    milestone = "starting milestone reached (20 clips; not proof)" if n >= 20 else f"{n}/20 clips toward the starting milestone"
    print(f"::notice title=Indian set::{'VALID' if not errors else 'INVALID'} · {n} clips ({test} test) · {milestone} · tags {tags}")
    return 1 if errors else 0

sys.exit(main())
