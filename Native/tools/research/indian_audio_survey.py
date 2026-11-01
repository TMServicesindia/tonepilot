"""Research only (CI): Wikimedia Commons audio candidates for Indian (and missing Western) instruments.
Reads metadata only (no audio downloaded): title, URL, MIME, size, licence, author, description.
Licence classes: eligible (CC0 / public domain / CC BY), review (CC BY-SA: share-alike terms for
derived models need review), excluded (NC / ND / unknown). Labels come from titles/descriptions and
are UNVERIFIED until a person listens. Writes docs/research/indian_audio_candidates.{json,md}."""
import json, os, re, time, urllib.parse, urllib.request

UA = {"User-Agent": "TonePilot-research/1.0 (instrument dataset survey; contact via GitHub repo)"}
INSTRUMENTS = ["tabla", "mridangam", "dholak", "ghatam", "kanjira", "thavil", "dhol", "bansuri", "nadaswaram",
               "shehnai", "veena", "sitar", "santoor", "tanpura", "sarangi", "viola", "harmonium", "mandolin carnatic"]

def get(params):
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({**params, "format": "json"})
    for i in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=40) as r:
                return json.loads(r.read())
        except Exception as e:
            err = str(e); time.sleep(2 * (i + 1))
    return {"error": err}

def lic_class(short, usage):
    t = f"{short} {usage}".lower()
    if any(k in t for k in ("-nc", " nc", "noncommercial", "non-commercial", "-nd", "noderiv")):
        return "excluded"
    if "cc0" in t or "public domain" in t or t.strip().startswith("pd"):
        return "eligible"
    if "by-sa" in t or "by sa" in t:
        return "review"
    if re.search(r"cc[ -]by[ -]?\d", t) or "cc by" in t or "attribution" in t:
        return "eligible"
    return "excluded"

out = {}
for inst in INSTRUMENTS:
    res = get({"action": "query", "generator": "search", "gsrsearch": f"{inst} filetype:audio", "gsrnamespace": 6, "gsrlimit": 50,
               "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata"})
    files = []
    for p in (res.get("query", {}).get("pages", {}) or {}).values():
        ii = (p.get("imageinfo") or [{}])[0]; md = ii.get("extmetadata", {})
        g = lambda k: re.sub(r"<[^>]+>", "", (md.get(k, {}) or {}).get("value", "") or "")[:200]
        short, usage = g("LicenseShortName"), g("UsageTerms")
        files.append({"title": p.get("title"), "url": ii.get("url"), "mime": ii.get("mime"), "bytes": ii.get("size"),
                      "licence": short or usage, "licence_url": g("LicenseUrl"), "class": lic_class(short, usage),
                      "author": g("Artist"), "description": g("ImageDescription"), "label_status": "UNVERIFIED (from title/description)"})
    out[inst] = {"files": files, "error": res.get("error")}
    print(f"COMMONS {inst}: {len(files)} audio files; eligible {sum(f['class']=='eligible' for f in files)}, review {sum(f['class']=='review' for f in files)}")
os.makedirs("docs/research", exist_ok=True)
json.dump(out, open("docs/research/indian_audio_candidates.json", "w"), indent=1, ensure_ascii=False)
L = ["# Indian instrument audio candidates — Wikimedia Commons (metadata only; labels UNVERIFIED)", "",
     "Eligible = CC0 / public domain / CC BY (attribution required). Review = CC BY-SA. Excluded = NC / ND / unknown.",
     "Search matches are not proof of the instrument: every clip needs listening verification before use.", "",
     "| Instrument | Audio files found | Eligible | Review (BY-SA) | Excluded |", "|---|---|---|---|---|"]
for inst, d in out.items():
    fs = d["files"]
    L.append(f"| {inst} | {len(fs)} | {sum(f['class']=='eligible' for f in fs)} | {sum(f['class']=='review' for f in fs)} | {sum(f['class']=='excluded' for f in fs)} |")
L += ["", "## Eligible files (first 8 per instrument)", ""]
for inst, d in out.items():
    el = [f for f in d["files"] if f["class"] == "eligible"][:8]
    if el:
        L.append(f"**{inst}**: " + "; ".join(f"[{f['title'][5:60]}]({f['url']}) ({f['licence']})" for f in el))
        L.append("")
open("docs/research/indian_audio_candidates.md", "w").write("\n".join(L) + "\n")
