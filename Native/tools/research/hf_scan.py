"""Research-only: licence, size and gating facts for candidate models/datasets from the public
Hugging Face and Zenodo APIs (plus a few licence pages). Writes docs/research/*.{json,md}.
Not part of the app; run by .github/workflows/model-research.yml."""
import json, re, sys, urllib.request, urllib.parse, os

UA = {"User-Agent": "TonePilot-research/1.0"}

def get(url, raw=False):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=40) as r:
            data = r.read()
            return data.decode("utf-8", "replace") if raw else json.loads(data)
    except Exception as e:  # record the failure, keep going
        return {"error": str(e)} if not raw else f"ERROR {e}"

MODELS = [
    # instrument / embedding
    "lukewys/laion_clap", "laion/clap-htsat-unfused", "laion/clap-htsat-fused", "laion/larger_clap_music",
    "laion/larger_clap_music_and_speech", "laion/larger_clap_general", "microsoft/msclap",
    "m-a-p/MERT-v1-95M", "m-a-p/MERT-v1-330M", "OpenMuQ/MuQ-large-msd-iter", "OpenMuQ/MuQ-MuLan-large",
    "MIT/ast-finetuned-audioset-10-10-0.4593", "fschmid56/EfficientAT", "google/yamnet",
    # rhythm / structure
    "CPJKU/beat_this", "taejunkim/allinone", "mir-aidj/all-in-one",
    # transcription / pitch
    "spotify/basic-pitch", "mimbres/YourMT3", "ChiTu/FCPE", "lj1995/VoiceConversionWebUI",
    "openvpi/SOME", "SonyCSLParis/pesto",
    # separation
    "KimberleyJensen/MelBandRoformer", "TRvlvr/model_repo", "Politrees/UVR_resources", "facebook/htdemucs",
]
DATASETS = ["Jacobvs/slakh2100", "Slakh/slakh2100", "google/nsynth", "jg583/NSynth", "amaai-lab/MusicBench",
            "mtg-upf/irmas", "AudioSet/audioset", "agkphysics/AudioSet", "marsyas/gtzan", "ccmusic-database/instrument_timbre",
            "ccmusic-database/Guzheng_Tech99", "ccmusic-database/song_structure", "mtg-jamendo/mtg-jamendo-dataset",
            "MLCommons/peoples_speech"]
SEARCHES = {
    "models": ["beat tracking", "downbeat", "chord recognition", "chord", "music transcription", "piano transcription",
               "guitar transcription", "basic pitch", "instrument recognition", "instrument classification",
               "musical instrument", "music tagging", "indian music", "carnatic", "hindustani", "raga", "tabla",
               "sitar", "music structure", "source separation", "melody extraction", "pitch estimation"],
    "datasets": ["instrument", "indian music", "carnatic", "hindustani", "chord", "beat", "music transcription",
                 "slakh", "nsynth", "irmas", "openmic", "musicnet", "guitarset", "maestro", "medleydb"],
}
ZENODO = {"PANNs checkpoints": "3987831", "MS-CLAP weights": "8378278", "Slakh2100": "4599666",
          "Beat This! spectrograms": "13922116", "MUSDB18-HQ": "3338373", "Mridangam stroke": "1265188"}
PAGES = {"NSynth": "https://magenta.tensorflow.org/datasets/nsynth",
         "Essentia models": "https://essentia.upf.edu/models.html",
         "Slakh site": "http://www.slakh.com/",
         "Beat This! README": "https://raw.githubusercontent.com/CPJKU/beat_this/main/README.md",
         "Basic Pitch NOTICE/LICENSE": "https://raw.githubusercontent.com/spotify/basic-pitch/main/LICENSE"}

def license_of(info):
    if not isinstance(info, dict) or "error" in info: return None
    card = info.get("cardData") or {}
    lic = card.get("license") or card.get("license_name")
    tags = [t[8:] for t in info.get("tags", []) if t.startswith("license:")]
    return lic or (tags[0] if tags else None)

def size_of(info):
    try:
        return sum((s.get("size") or 0) for s in info.get("siblings", []))
    except Exception:
        return None

out = {"models": {}, "datasets": {}, "searches": {}, "zenodo": {}, "pages": {}}
for m in MODELS:
    info = get(f"https://huggingface.co/api/models/{m}?blobs=true")
    card = get(f"https://huggingface.co/{m}/raw/main/README.md", raw=True)
    lic_lines = [l.strip() for l in card.splitlines() if re.search(r"licen[cs]e|commercial|non-commercial|cc-by|research", l, re.I)][:8] if isinstance(card, str) else []
    out["models"][m] = {"error": info.get("error") if isinstance(info, dict) else None, "license": license_of(info),
                        "gated": info.get("gated") if isinstance(info, dict) else None,
                        "downloads": info.get("downloads") if isinstance(info, dict) else None,
                        "lastModified": info.get("lastModified") if isinstance(info, dict) else None,
                        "bytes": size_of(info) if isinstance(info, dict) else None,
                        "files": [(s.get("rfilename"), s.get("size")) for s in info.get("siblings", [])][:25] if isinstance(info, dict) else [],
                        "card_license_lines": lic_lines}
for d in DATASETS:
    info = get(f"https://huggingface.co/api/datasets/{d}")
    out["datasets"][d] = {"error": info.get("error") if isinstance(info, dict) else None, "license": license_of(info),
                          "gated": info.get("gated") if isinstance(info, dict) else None,
                          "downloads": info.get("downloads") if isinstance(info, dict) else None}
for kind, terms in SEARCHES.items():
    for term in terms:
        q = urllib.parse.quote(term)
        res = get(f"https://huggingface.co/api/{kind}?search={q}&limit=15&sort=downloads&direction=-1&full=true")
        rows = []
        if isinstance(res, list):
            for r in res:
                rows.append({"id": r.get("id"), "license": license_of(r), "downloads": r.get("downloads"),
                             "pipeline": r.get("pipeline_tag"), "gated": r.get("gated")})
        out["searches"][f"{kind}:{term}"] = rows if rows else res
for name, rec in ZENODO.items():
    info = get(f"https://zenodo.org/api/records/{rec}")
    meta = info.get("metadata", {}) if isinstance(info, dict) else {}
    files = info.get("files", []) if isinstance(info, dict) else []
    out["zenodo"][name] = {"record": rec, "error": info.get("error") if isinstance(info, dict) else None,
                           "title": meta.get("title"), "license": (meta.get("license") or {}).get("id"),
                           "access": meta.get("access_right"),
                           "files": [(f.get("key"), f.get("size")) for f in files][:20]}
for name, url in PAGES.items():
    text = get(url, raw=True)
    lines = [re.sub(r"<[^>]+>", " ", l).strip() for l in text.splitlines() if re.search(r"licen[cs]e|commercial|creative commons|cc by|cc-by", l, re.I)][:12] if isinstance(text, str) else []
    out["pages"][name] = {"url": url, "lines": lines, "error": text[:120] if isinstance(text, str) and text.startswith("ERROR") else None}

os.makedirs("docs/research", exist_ok=True)
json.dump(out, open("docs/research/model_scan.json", "w"), indent=1)
with open("docs/research/model_scan.md", "w") as f:
    f.write("# Model and dataset licence scan (automated, research only)\n\nGenerated by Native/tools/research/hf_scan.py in CI from public APIs. Facts as reported by each host at scan time.\n\n## Models\n\n| Model | Licence (card) | Gated | Size | Downloads | Card licence lines |\n|---|---|---|---|---|---|\n")
    for m, r in out["models"].items():
        size = f"{(r['bytes'] or 0)/1e6:.0f} MB" if r.get("bytes") else "-"
        f.write(f"| {m} | {r['license'] or ('ERROR' if r['error'] else '-')} | {r['gated']} | {size} | {r['downloads']} | {' / '.join(r['card_license_lines'])[:200].replace('|','/')} |\n")
    f.write("\n## Datasets\n\n| Dataset | Licence | Gated | Downloads |\n|---|---|---|---|\n")
    for d, r in out["datasets"].items():
        f.write(f"| {d} | {r['license'] or ('ERROR' if r['error'] else '-')} | {r['gated']} | {r['downloads']} |\n")
    f.write("\n## Zenodo\n\n| Item | Record | Licence | Access | Files |\n|---|---|---|---|---|\n")
    for n, r in out["zenodo"].items():
        f.write(f"| {n} | {r['record']} | {r['license'] or r['error']} | {r['access']} | {', '.join(str(k) for k, _ in r['files'][:5])} |\n")
    f.write("\n## Licence pages\n\n")
    for n, r in out["pages"].items():
        f.write(f"**{n}** ({r['url']}): {' / '.join(r['lines'])[:600] or r['error']}\n\n")
    f.write("\n## Hugging Face searches (top by downloads)\n\n")
    for k, rows in out["searches"].items():
        f.write(f"**{k}**: ")
        if isinstance(rows, list):
            f.write("; ".join(f"{x['id']} ({x['license'] or '-'})" for x in rows[:15]))
        else:
            f.write(str(rows)[:200])
        f.write("\n\n")
print("done")
