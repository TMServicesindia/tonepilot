"""TonePilot real-instrument sound packs (phase 1), built in CI from CC0 libraries.

Sources (CC0 1.0, LICENSE files read 2 Nov 2026):
  VSCO 2 Community Edition  https://github.com/sgossner/VSCO-2-CE   (strings sections, flute)
  Versilian Community Sample Library (VCSL)  https://github.com/sgossner/VCSL   (Steinway B grand)

The libraries ship WAV files only (no SFZ); note, velocity layer and take are in the file names:
  VlnEns_susVib_A3_v1.wav · LDFlute_susvib_C4_v1_1.wav · JHPiano_Sus_Close_C4_vl3_rr1.wav
Octave conventions differ (measured 3 Nov): VSCO names middle C "C3", VCSL names it "C4". Every root
is read from its name with the library's convention and then CONFIRMED against the sample's
measured pitch (allowing for detection landing on a harmonic); a sample that does not fit is dropped.

Processing per sample: mono, 32 kHz, leading silence trimmed, cut to the pack's length; sustained
instruments get a loop in their steady part (best-matching end point, baked crossfade); decaying
instruments (piano) fade out. One gain per pack (velocity layers keep their relative levels).
Output per pack: <id>/pack.json + <id>/*.flac (shipped) and wav/<id>/*.wav (CI only, for embeddings).
Usage: build_packs.py <VSCO-2-CE dir> <VCSL dir> <out dir> [--commits vsco=<sha>,vcsl=<sha>]"""
import hashlib, json, os, re, sys, uuid
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

SR = 32000
NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
NS = uuid.UUID("6f1d3b7e-2c4a-4e8b-9a51-7d0c5e2f9a10")   # fixed: tone ids stay the same across rebuilds

PACKS = [
    {"id": "vsco-strings", "name": "Real String Section", "family": "strings", "library": "vsco", "loop": True, "seconds": 5.0,
     "sources": [("Strings/Cello Section/susvib", None, 54), ("Strings/Viola Section/susvib", 55, 66),
                 ("Strings/Violin Section/susVib", 67, None)],
     "tones": [{"key": "ensemble", "name": "Real Strings (VSCO)", "envelope": {"attack": 0.01, "decay": 0.3, "sustain": 1.0, "release": 0.45}},
               {"key": "slow", "name": "Real Slow Strings (VSCO)", "envelope": {"attack": 0.35, "decay": 0.3, "sustain": 1.0, "release": 1.2}}]},
    {"id": "vcsl-steinway", "name": "Steinway Grand Piano", "family": "piano", "library": "vcsl", "loop": False, "seconds": 7.0,
     "sources": [("Chordophones/Zithers/Grand Piano, Steinway B/Sus", None, None)], "layers": [2, 4],
     "tones": [{"key": "grand", "name": "Steinway Grand (VCSL)", "envelope": {"attack": 0.001, "decay": 0.3, "sustain": 1.0, "release": 0.35}}]},
    {"id": "vsco-flute", "name": "Real Flute", "family": "flute", "library": "vsco", "loop": True, "seconds": 4.0,
     "sources": [("Woodwinds/Flute/susvib", None, None)],
     "tones": [{"key": "flute", "name": "Real Flute (VSCO)", "envelope": {"attack": 0.02, "decay": 0.3, "sustain": 1.0, "release": 0.25}}]},
]
OCTAVE_OFFSET = {"vsco": 2, "vcsl": 1}   # MIDI = 12 * (octave + offset) + pitch class
NAME = re.compile(r"_([A-G]#?)(-?\d)_v[l]?(\d+)(?:_(?:rr)?(\d+))?\.wav$", re.I)


def detect_f0(x, expected):
    """Strongest spectral peak. High notes decay fast (a piano's top octave is mostly gone after
    0.3 s), so they are measured right after the attack; others in their steady part."""
    if expected > 700:
        seg = x[int(0.02 * SR):int(0.32 * SR)]
    else:
        seg = x[int(0.4 * SR):int(1.4 * SR)] if len(x) > int(1.4 * SR) else x
    n = 1 << 17
    spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), n=n))
    freqs = np.fft.rfftfreq(n, 1 / SR)
    keep = (freqs > max(25, expected * 0.45)) & (freqs < min(SR / 2 - 100, expected * 7))   # ignore rumble far below the note
    return float(freqs[np.argmax(spec * keep)])


def pitch_fits(f0, midi):
    """Measured peak must sit on the expected note or one of its first 6 harmonics (±3 %)."""
    expected = 440 * 2 ** ((midi - 69) / 12)
    r = f0 / expected
    return any(abs(r / k - 1) < 0.03 for k in range(1, 7))


def load(path):
    x, sr = sf.read(path, dtype="float32", always_2d=True)
    x = x.mean(1)
    g = np.gcd(SR, sr)
    return resample_poly(x, SR // g, sr // g).astype(np.float32)


def trim(x, seconds, loop, f0):
    env = np.abs(x)
    thr = env.max() * 10 ** (-50 / 20)
    on = int(np.argmax(env > thr))
    x = x[max(0, on - int(0.005 * SR)):]
    n = min(len(x), int(seconds * SR))
    x = x[:n].copy()
    if not loop:
        fade = min(n // 3, int(0.8 * SR))
        x[n - fade:] *= np.linspace(1, 0, fade, dtype=np.float32) ** 2
        return x, None
    # Loop in the steady part: start at 45 %, end near 90 %, end point = best match of the waveform
    # around the start (search one period either side); 60 ms crossfade baked before the end.
    period = max(8, int(SR / max(f0, 40)))
    s0 = int(0.45 * n)
    target = int(0.9 * n)
    w = min(period * 4, int(0.02 * SR))
    ref = x[s0:s0 + w]
    best, best_c = target, -2.0
    for e in range(target - period, target + period):
        if e + w > n:
            break
        seg = x[e:e + w]
        c = float(np.dot(ref, seg) / (np.linalg.norm(ref) * np.linalg.norm(seg) + 1e-9))
        if c > best_c:
            best, best_c = e, c
    xf = min(int(0.06 * SR), best - s0 - 1)
    t = np.linspace(0, 1, xf, dtype=np.float32)
    x[best - xf:best] = x[best - xf:best] * (1 - t) + x[s0 - xf:s0] * t   # the end runs into what precedes the start
    return x[:best + 1], (s0, best)


def zones_for(entries, lo_bound, hi_bound):
    """Key range per root: halfway to the neighbours, clamped to the source's bounds."""
    roots = sorted({e["root"] for e in entries})
    ranges = {}
    for i, r in enumerate(roots):
        lo = 0 if i == 0 else (roots[i - 1] + r) // 2 + 1
        hi = 127 if i == len(roots) - 1 else (r + roots[i + 1]) // 2
        lo, hi = max(lo, lo_bound or 0), min(hi, 127 if hi_bound is None else hi_bound)
        if lo <= hi:            # a root wholly outside the source's bounds plays no keys
            ranges[r] = (lo, hi)
    return ranges


def velocity_ranges(layers):
    if len(layers) == 1:
        return {layers[0]: (1, 127)}
    if len(layers) == 2:
        return {layers[0]: (1, 84), layers[1]: (85, 127)}
    cuts = np.linspace(1, 128, len(layers) + 1).astype(int)
    return {v: (int(cuts[i]), int(cuts[i + 1] - 1)) for i, v in enumerate(layers)}


def build(pack, roots, out, commits):
    lib = roots[pack["library"]]
    pdir = os.path.join(out, "packs", pack["id"]); wdir = os.path.join(out, "wav", pack["id"])
    os.makedirs(pdir, exist_ok=True); os.makedirs(wdir, exist_ok=True)
    rendered, dropped, zones = [], [], []
    bounds = []
    for src, lo_b, hi_b in pack["sources"]:
        d = os.path.join(lib, src)
        entries = []
        for f in sorted(os.listdir(d)):
            m = NAME.search(f)
            if not m:
                continue
            take = int(m.group(4) or 1)
            if take != 1:
                continue
            root = 12 * (int(m.group(2)) + OCTAVE_OFFSET[pack["library"]]) + NOTE[m.group(1).upper()]
            entries.append({"file": f, "root": root, "layer": int(m.group(3))})
        layers = sorted({e["layer"] for e in entries})
        if "layers" in pack:
            layers = [l for l in layers if l in pack["layers"]]
        layers = [layers[0], layers[-1]] if len(layers) > 2 else layers
        entries = [e for e in entries if e["layer"] in layers]
        kr = zones_for(entries, lo_b, hi_b)
        vr = velocity_ranges(layers)
        entries = [e for e in entries if e["root"] in kr]
        for e in entries:
            x = load(os.path.join(d, e["file"]))
            f0 = detect_f0(x, 440 * 2 ** ((e["root"] - 69) / 12))
            if not pitch_fits(f0, e["root"]):
                dropped.append(f"{e['file']}: name says MIDI {e['root']}, measured peak {f0:.1f} Hz")
                continue
            expected = 440 * 2 ** ((e["root"] - 69) / 12)
            y, loop = trim(x, pack["seconds"], pack["loop"], expected)
            name = f"{e['root']:03d}_v{e['layer']}.flac"
            rendered.append((name, y))
            zones.append({"fileName": f"packs/{pack['id']}/{name}", "rootNote": e["root"],
                          "keyRange": {"low": kr[e["root"]][0], "high": kr[e["root"]][1]},
                          "velocityRange": {"low": vr[e["layer"]][0], "high": vr[e["layer"]][1]},
                          "startFrame": 0, "endFrame": None,
                          "loopStart": loop[0] if loop else None, "loopEnd": loop[1] if loop else None,
                          "source": f"{src}/{e['file']}"})
        bounds.append((src, len(entries)))
    peak = max(float(np.abs(y).max()) for _, y in rendered)
    gain = 0.9 / peak
    files = {}
    for name, y in rendered:
        y = np.clip(y * gain, -1, 1)
        sf.write(os.path.join(pdir, name), y, SR, subtype="PCM_16", format="FLAC")
        sf.write(os.path.join(wdir, name.replace(".flac", ".wav")), y, SR, subtype="PCM_16")
        data = open(os.path.join(pdir, name), "rb").read()
        files[name] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data), "frames": len(y)}
    tones = [{"id": str(uuid.uuid5(NS, f"{pack['id']}/{t['key']}")).upper(), "name": t["name"], "family": pack["family"],
              "envelope": t["envelope"], "zones": [{k: v for k, v in z.items() if k != "source"} for z in zones]} for t in pack["tones"]]
    lib_url = {"vsco": "https://github.com/sgossner/VSCO-2-CE", "vcsl": "https://github.com/sgossner/VCSL"}[pack["library"]]
    manifest = {"format": 1, "id": pack["id"], "version": 1, "name": pack["name"], "family": pack["family"], "sampleRate": SR,
                "source": {"library": lib_url, "license": "CC0-1.0", "commit": commits.get(pack["library"], "unknown"),
                           "files": sorted(z["source"] for z in zones)},
                "tones": tones, "files": files}
    json.dump(manifest, open(os.path.join(pdir, "pack.json"), "w"), indent=1)
    total = sum(f["bytes"] for f in files.values())
    print(f"PACK {pack['id']}: {len(rendered)} samples, {len(dropped)} dropped by the pitch check, "
          f"{total / 1e6:.1f} MB FLAC, layers per source {bounds}")
    for d in dropped:
        print(f"  DROPPED {d}")
    return {"id": pack["id"], "samples": len(rendered), "dropped": len(dropped), "mb": round(total / 1e6, 2)}


if __name__ == "__main__":
    vsco, vcsl, out = sys.argv[1:4]
    commits = {}
    if "--commits" in sys.argv:
        commits = dict(kv.split("=") for kv in sys.argv[sys.argv.index("--commits") + 1].split(","))
    roots = {"vsco": vsco, "vcsl": vcsl}
    summary = [build(p, roots, out, commits) for p in PACKS]
    json.dump(summary, open(os.path.join(out, "summary.json"), "w"), indent=1)
