"""Ground-truth annotation checks and coverage report (research only).
Usage: annotations.py <annotations dir> [--catalogue <dir with *.jsonl>]
Checks every <song_id>.json against the taxonomy and schema rules, then prints the coverage report:
songs collected / imported / analysed / verified / partial / excluded, sections and events with
reliable labels — per language. Only verified events may count in accuracy."""
import glob, json, os, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
TAX = json.load(open(os.path.join(HERE, "..", "instruments", "taxonomy.json")))
FAM = TAX["families"]; ALL = {i for v in FAM.values() for i in v}


def check(a):
    e = []
    sid = a.get("song_id", "?")
    for k in ("song_id", "language", "audio_sha256", "annotator", "verification", "events"):
        if k not in a: e.append(f"{sid}: missing {k}")
    if a.get("language") not in ("ta", "te", "hi"): e.append(f"{sid}: language must be ta/te/hi")
    if not str(a.get("song_id", "")).startswith(str(a.get("language", "")) + "-"): e.append(f"{sid}: song_id must start with the language code")
    for ev in a.get("events", []):
        if not (0 <= ev.get("start", -1) < ev.get("end", -1)): e.append(f"{sid}: bad time range {ev}")
        if ev.get("family") not in FAM: e.append(f"{sid}: unknown family {ev.get('family')!r}")
        if ev.get("level") == "instrument":
            if ev.get("label") not in ALL: e.append(f"{sid}: unknown instrument {ev.get('label')!r}")
            elif ev.get("label") not in FAM.get(ev.get("family"), []): e.append(f"{sid}: {ev['label']} is not in family {ev.get('family')}")
        elif ev.get("level") == "family" and ev.get("label") != ev.get("family"):
            e.append(f"{sid}: family-level event must have label == family")
        if ev.get("source") not in ("acoustic", "electronic", "imitation", "unknown"): e.append(f"{sid}: bad source")
        if ev.get("audibility") not in ("clear", "partial", "uncertain"): e.append(f"{sid}: bad audibility")
        if not 0 <= ev.get("confidence", -1) <= 1: e.append(f"{sid}: confidence 0…1")
    return e


def main(d, cat_dir=None):
    errors, by_lang = [], defaultdict(Counter)
    hashes = {}
    for f in sorted(glob.glob(os.path.join(d, "*.json"))):
        a = json.load(open(f)); errors += check(a)
        h = a.get("audio_sha256")
        if h in hashes: errors.append(f"{a.get('song_id')}: same audio as {hashes[h]}")
        hashes[h] = a.get("song_id")
        c = by_lang[a.get("language", "?")]
        c["annotated"] += 1; c[a.get("verification", "unverified")] += 1
        c["sections"] += len(a.get("sections", []))
        c["events"] += len(a.get("events", []))
        c["reliable_events"] += sum(1 for ev in a.get("events", []) if a.get("verification") == "verified" and ev.get("audibility") != "uncertain")
    if cat_dir:
        for f in glob.glob(os.path.join(cat_dir, "*.jsonl")):
            for line in open(f):
                if not line.strip(): continue
                s = json.loads(line); c = by_lang[s.get("language", "?")]
                c["collected"] += 1
                for tier in ("imported", "analysed", "excluded"):
                    c[tier] += int(s.get("status") == tier or tier in s.get("tiers", []))
    for x in errors: print(f"::error title=Annotations::{x}")
    print("| Language | Collected | Imported | Analysed | Annotated | Verified | Partial | Excluded | Sections | Events | Reliable events |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for lang in ("ta", "te", "hi"):
        c = by_lang[lang]
        print(f"| {lang} | {c['collected']} | {c['imported']} | {c['analysed']} | {c['annotated']} | {c['verified']} | {c['partial']} | {c['excluded']} | {c['sections']} | {c['events']} | {c['reliable_events']} |")
    return 1 if errors else 0


if __name__ == "__main__":
    a = sys.argv
    sys.exit(main(a[1], a[a.index("--catalogue") + 1] if "--catalogue" in a else None))
