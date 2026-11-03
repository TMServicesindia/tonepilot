"""Adds each pack's search embeddings (from `tone_t1.py --export-tables` on the SoundPackDump) to its
pack.json, so an installed pack joins the app's nearest-sound search.
Usage: merge_embeddings.py <packs root> <dump dir> <tables dir>"""
import json, os, sys

root, dump, tables = sys.argv[1:4]
clips = json.load(open(os.path.join(dump, "table.json")))
pack_of = {c["patch"]: c["pack"] for c in clips}
docs = {k: json.load(open(os.path.join(tables, f"tone_table_{k}.json"))) for k in ("harmonic", "plain")}
for pid in sorted(os.listdir(os.path.join(root, "packs"))):
    path = os.path.join(root, "packs", pid, "pack.json")
    pack = json.load(open(path))
    emb = {k: [e for e in docs[k]["entries"] if pack_of.get(e["patch"]) == pid] for k in docs}
    assert emb["harmonic"] and len(emb["harmonic"]) == len(emb["plain"]), pid
    assert docs["harmonic"]["embeddingDim"] == 960, docs["harmonic"]["embeddingDim"]
    pack["embeddings"] = emb
    json.dump(pack, open(path, "w"), separators=(",", ":"))
    print(f"EMBED {pid}: {len(emb['harmonic'])} entries per table (tones x 3 registers)")
