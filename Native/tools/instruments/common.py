"""Shared helpers for the instrument-recognition proxy benchmark (research only, CI).
Taxonomy, one label map for Apple SoundAnalysis and AudioSet-trained models (YAMNet, EfficientAT,
PANNs), windowing and WAV I/O. No audio is downloaded here."""
import json, os, re, wave
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
WIN, HOP = 1.0, 0.5   # analysis window and hop in seconds (time-based detection)


def taxonomy():
    t = json.load(open(os.path.join(HERE, "taxonomy.json")))
    instruments = sorted({i for fam in t["families"].values() for i in fam})
    families = sorted(t["families"])
    fam_of = {i: f for f, items in t["families"].items() for i in items}
    return t, instruments, families, fam_of


def norm(label):
    """'Violin, fiddle' and 'violin_fiddle' → 'violin_fiddle' (Apple ids follow AudioSet names)."""
    return re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_")


# Model label → (instrument or None, family). Keys are normalised label names. Only labels whose meaning
# is clear are mapped; everything else is ignored (no guessing Indian names from generic labels).
LABEL_MAP = {
    "piano": ("piano", "Keys"), "electric_piano": ("electric piano", "Keys"), "keyboard_musical": (None, "Keys"),
    "organ": ("organ", "Keys"), "electronic_organ": ("organ", "Keys"), "hammond_organ": ("organ", "Keys"),
    "harpsichord": (None, "Keys"), "accordion": ("accordion", "Keys"), "harmonium": ("harmonium", "Keys"),
    "synthesizer": (None, "Electronic"), "sampler": (None, "Electronic"), "theremin": (None, "Electronic"),
    "guitar": ("guitar", "Other plucked"), "acoustic_guitar": ("guitar", "Other plucked"),
    "electric_guitar": ("electric guitar", "Other plucked"), "steel_guitar_slide_guitar": ("guitar", "Other plucked"),
    "bass_guitar": ("bass guitar", "Bass"), "banjo": (None, "Other plucked"), "ukulele": (None, "Other plucked"),
    "zither": (None, "Other plucked"), "plucked_string_instrument": (None, "Other plucked"), "strum": (None, "Other plucked"),
    "sitar": ("sitar", "Indian plucked"), "mandolin": ("mandolin", "Other plucked"), "harp": ("harp", "Other plucked"),
    "violin_fiddle": ("violin", "Strings"), "violin": ("violin", "Strings"), "cello": ("cello", "Strings"),
    "double_bass": ("double bass", "Strings"), "string_section": ("string ensemble", "Strings"),
    "bowed_string_instrument": (None, "Strings"), "pizzicato": ("string ensemble", "Strings"),
    "flute": ("flute", "Western winds"), "clarinet": ("clarinet", "Western winds"), "saxophone": ("saxophone", "Western winds"),
    "alto_saxophone": ("saxophone", "Western winds"), "oboe": ("oboe", "Western winds"),
    "wind_instrument_woodwind_instrument": (None, "Western winds"), "harmonica": (None, "Western winds"),
    "brass_instrument": (None, "Other"), "french_horn": ("french horn", "Other"), "trumpet": ("trumpet", "Other"),
    "trombone": ("trombone", "Other"), "choir": ("choir", "Other"), "choir_singing": ("choir", "Other"),
    "glockenspiel": ("glockenspiel", "Bells"), "vibraphone": ("vibraphone", "Bells"), "marimba_xylophone": ("marimba", "Bells"),
    "tubular_bells": ("tubular bells", "Bells"), "mallet_percussion": (None, "Bells"), "bell": (None, "Bells"),
    "chime": (None, "Bells"), "wind_chime": (None, "Bells"), "steelpan": (None, "Bells"), "music_box": ("music box", "Bells"),
    "drum_kit": ("drums", "Other percussion"), "drum": (None, "Other percussion"), "snare_drum": ("drums", "Other percussion"),
    "bass_drum": ("drums", "Other percussion"), "hi_hat": ("drums", "Other percussion"), "cymbal": ("drums", "Other percussion"),
    "drum_machine": ("electronic percussion", "Other percussion"), "percussion": (None, "Other percussion"),
    "tabla": ("tabla", "Indian percussion"),
}
ELECTRONIC_LABELS = {"synthesizer", "sampler", "theremin", "electronic_music", "electronic_organ", "drum_machine"}


def map_scores(label_names, scores, instruments, families):
    """Per-window model label scores [W×L] → taxonomy instrument [W×I] and family [W×F] scores (max over
    mapped labels) and an electronic-vs-acoustic score [W×2]."""
    scores = np.asarray(scores, dtype=np.float32)
    W = scores.shape[0]
    inst = np.zeros((W, len(instruments)), np.float32); fam = np.zeros((W, len(families)), np.float32)
    elec = np.zeros(W, np.float32); acou = np.zeros(W, np.float32)
    ii = {n: k for k, n in enumerate(instruments)}; fi = {n: k for k, n in enumerate(families)}
    for j, name in enumerate(label_names):
        n = norm(name)
        if n in ELECTRONIC_LABELS:
            elec = np.maximum(elec, scores[:, j])
        if n not in LABEL_MAP:
            continue
        i, f = LABEL_MAP[n]
        if i is not None and i in ii:
            inst[:, ii[i]] = np.maximum(inst[:, ii[i]], scores[:, j])
        if f in fi:
            fam[:, fi[f]] = np.maximum(fam[:, fi[f]], scores[:, j])
        if n not in ELECTRONIC_LABELS:
            acou = np.maximum(acou, scores[:, j])
    return inst, fam, np.stack([acou, elec], 1)


def read_wav(path):
    with wave.open(path) as w:
        sr, n = w.getframerate(), w.getnframes()
        x = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float32) / 32767.0
        if w.getnchannels() > 1:
            x = x.reshape(-1, w.getnchannels()).mean(1)
    return x, sr


def write_wav(path, x, sr):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.clip(x / max(1e-6, np.abs(x).max()) * 0.9, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def resample(x, sr, target):
    if sr == target:
        return x
    import scipy.signal as ss
    from math import gcd
    g = gcd(int(sr), int(target))
    return ss.resample_poly(x, int(target) // g, int(sr) // g).astype(np.float32)


def windows(x, sr):
    """Window start times and slices (WIN s, HOP s); a clip shorter than WIN gives one padded window."""
    n, h = int(WIN * sr), int(HOP * sr)
    if len(x) <= n:
        return [0.0], [np.pad(x, (0, n - len(x)))]
    starts = list(range(0, len(x) - n + 1, h))
    return [s / sr for s in starts], [x[s:s + n] for s in starts]


def load_clips(root):
    return json.load(open(os.path.join(root, "clips.json")))
