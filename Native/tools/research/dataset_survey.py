"""Research only (CI): survey candidate Tamil / Indian music datasets for the acceptance set.
For every candidate it records what is ACTUALLY in it (file types, audio file count, whether
parquet shards embed an audio column), the declared licence, gating/access rules and size.
Reads public APIs only (Hugging Face, Zenodo). Downloads no audio.
Writes docs/research/dataset_survey.{json,md}."""
import json, urllib.request, urllib.parse, collections, os

UA = {"User-Agent": "TonePilot-research/1.0"}
AUDIO = {"wav", "mp3", "flac", "ogg", "m4a", "aac", "opus", "aif", "aiff", "wma"}

def get(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=40) as r:
            return json.loads(r.read().decode("utf-8", "replace"))
    except Exception as e:
        return {"error": str(e)}

HF_QUERIES = ["tamil", "tamil music", "tamil song", "tamil film", "kollywood", "tamil audio", "carnatic",
              "indian music", "indian film music", "bollywood", "hindustani", "mridangam", "tabla", "raga", "tala",
              "veena", "indian classical", "telugu song", "hindi song", "saraga"]
HF_EXPLICIT = ["Thanushs25/tamil-audio-emotion-classification"]
ZENODO_QUERIES = ["tamil music", "carnatic", "saraga", "indian art music", "tamil film songs", "mridangam", "indian music dataset", "tala"]

def hf_dataset(did):
    info = get(f"https://huggingface.co/api/datasets/{urllib.parse.quote(did, safe='/')}?full=true")
    if "error" in info:
        return {"id": did, "error": info["error"]}
    files = [s.get("rfilename", "") for s in info.get("siblings", [])]
    ext = collections.Counter(f.rsplit(".", 1)[-1].lower() for f in files if "." in f)
    card = info.get("cardData") or {}
    lic = card.get("license") or [t.split(":", 1)[1] for t in info.get("tags", []) if t.startswith("license:")]
    feats = json.dumps(card.get("dataset_info", ""))[:4000]
    audio_col = '"audio"' in feats or "'audio'" in feats or "Audio" in feats
    return {"id": did, "license": lic, "gated": info.get("gated"), "private": info.get("private"),
            "downloads": info.get("downloads"), "files": len(files), "ext": dict(ext.most_common(8)),
            "audio_files": sum(v for k, v in ext.items() if k in AUDIO),
            "parquet_with_audio_feature": bool(ext.get("parquet")) and audio_col,
            "tags": [t for t in info.get("tags", []) if t.split(":")[0] in ("task_categories", "language", "modality", "size_categories")][:10],
            "sample_files": files[:6], "description": (card.get("pretty_name") or "")[:120]}

def main():
    out = {"huggingface": [], "zenodo": [], "notes": []}
    seen = set()
    for did in HF_EXPLICIT:
        seen.add(did); out["huggingface"].append(hf_dataset(did))
    for q in HF_QUERIES:
        res = get(f"https://huggingface.co/api/datasets?search={urllib.parse.quote(q)}&limit=40")
        if isinstance(res, dict):
            out["notes"].append(f"HF search {q!r} failed: {res.get('error')}"); continue
        for d in res:
            if d["id"] not in seen:
                seen.add(d["id"]); out["huggingface"].append(hf_dataset(d["id"]))
    zseen = set()
    for q in ZENODO_QUERIES:
        res = get(f"https://zenodo.org/api/records?q={urllib.parse.quote(q)}&size=25&type=dataset")
        for h in (res.get("hits", {}) or {}).get("hits", []) if isinstance(res, dict) else []:
            if h["id"] in zseen: continue
            zseen.add(h["id"])
            md = h.get("metadata", {}); files = h.get("files", []) or []
            ext = collections.Counter(f.get("key", "").rsplit(".", 1)[-1].lower() for f in files)
            out["zenodo"].append({"id": h["id"], "title": md.get("title", "")[:140], "license": (md.get("license") or {}).get("id"),
                                  "access": md.get("access_right"), "files": len(files), "ext": dict(ext.most_common(6)),
                                  "audio_files": sum(v for k, v in ext.items() if k in AUDIO),
                                  "size_mb": round(sum(f.get("size", 0) for f in files) / 1e6, 1), "url": h.get("links", {}).get("self_html")})
    os.makedirs("docs/research", exist_ok=True)
    json.dump(out, open("docs/research/dataset_survey.json", "w"), indent=1, ensure_ascii=False)
    with open("docs/research/dataset_survey.md", "w") as f:
        f.write("# Dataset survey (CI, public APIs; no audio downloaded)\n\n## Hugging Face\n\n| Dataset | Licence | Gated | Audio files | Parquet+audio | Files (ext) |\n|---|---|---|---|---|---|\n")
        for d in out["huggingface"]:
            if "error" in d: f.write(f"| {d['id']} | ERROR {d['error'][:60]} | | | | |\n"); continue
            f.write(f"| {d['id']} | {d['license']} | {d['gated']} | {d['audio_files']} | {d['parquet_with_audio_feature']} | {d['files']} {d['ext']} |\n")
        f.write("\n## Zenodo\n\n| Record | Title | Licence | Access | Audio files | Size MB |\n|---|---|---|---|---|---|\n")
        for z in out["zenodo"]:
            f.write(f"| {z['id']} | {z['title']} | {z['license']} | {z['access']} | {z['audio_files']} | {z['size_mb']} |\n")
        for n in out["notes"]: f.write(f"\n- {n}")
    print(f"HF {len(out['huggingface'])} datasets, Zenodo {len(out['zenodo'])} records")

main()
