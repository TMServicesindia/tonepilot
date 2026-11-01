"""Per-window outputs of one pretrained model for every clip (research only, CI).
Saves <out>/<model>.npz with, per clip: window starts, mapped taxonomy scores (approach A) and
embeddings (input to approach C), plus timing and model-size facts.
Usage: embed.py <render dir> <model: yamnet|efficientat|panns|clap> <out dir> [--eat <EfficientAT repo>]"""
import json, os, sys, time
import numpy as np
from common import taxonomy, map_scores, read_wav, resample, windows, load_clips, WIN

_, INSTRUMENTS, FAMILIES, FAM_OF = taxonomy()


class YAMNet:
    sr = 16000
    def __init__(self):
        import tensorflow_hub as hub, csv, io, tensorflow as tf
        self.tf = tf
        self.m = hub.load("https://tfhub.dev/google/yamnet/1")
        path = self.m.class_map_path().numpy().decode()
        self.labels = [r["display_name"] for r in csv.DictReader(io.StringIO(tf.io.read_file(path).numpy().decode()))]
        self.params = int(sum(np.prod(v.shape) for v in self.m.variables)) if hasattr(self.m, "variables") else None
    def __call__(self, wins):
        S, E = [], []
        for w in wins:
            s, e, _ = self.m(w.astype(np.float32))
            S.append(s.numpy().mean(0)); E.append(e.numpy().mean(0))
        return np.stack(S), np.stack(E)


class EfficientAT:
    sr = 32000
    def __init__(self, repo, name="mn10_as"):
        sys.path.insert(0, repo)
        import torch
        from models.mn.model import get_model
        from models.preprocess import AugmentMelSTFT
        from helpers.utils import NAME_TO_WIDTH, labels
        self.torch = torch
        self.m = get_model(width_mult=NAME_TO_WIDTH(name), pretrained_name=name).eval()
        self.mel = AugmentMelSTFT(n_mels=128, sr=32000, win_length=800, hopsize=320).eval()
        self.labels = list(labels)
        self.params = int(sum(p.numel() for p in self.m.parameters()))
    def __call__(self, wins):
        with self.torch.no_grad():
            x = self.torch.from_numpy(np.stack(wins).astype(np.float32))
            spec = self.mel(x)
            logits, feats = self.m(spec.unsqueeze(1))
            return self.torch.sigmoid(logits).numpy(), feats.reshape(len(wins), -1).numpy()


class PANNs:
    sr = 32000
    def __init__(self):
        from panns_inference import AudioTagging, labels
        self.m = AudioTagging(checkpoint_path=None, device="cpu")
        self.labels = list(labels)
        self.params = int(sum(p.numel() for p in self.m.model.parameters()))
    def __call__(self, wins):
        clip, emb = self.m.inference(np.stack(wins).astype(np.float32))
        return clip, emb


class CLAP:
    sr = 48000
    def __init__(self, name="laion/larger_clap_music"):
        import torch
        from transformers import ClapModel, ClapProcessor
        self.torch = torch
        self.m = ClapModel.from_pretrained(name).eval()
        self.p = ClapProcessor.from_pretrained(name)
        self.params = int(sum(p.numel() for p in self.m.audio_model.parameters()) + sum(p.numel() for p in self.m.audio_projection.parameters()))
        # Zero-shot "labels" = taxonomy instruments described in words, plus source prompts.
        self.labels = [f"the sound of a {i}" for i in INSTRUMENTS]
        self.source_prompts = ["a recording of a real acoustic musical instrument", "an electronic synthesizer sound",
                               "a synthesizer imitating a traditional Indian instrument"]
        with torch.no_grad():
            t = self.p(text=self.labels + self.source_prompts, return_tensors="pt", padding=True)
            te = self.m.get_text_features(**t)
            self.text = (te / te.norm(dim=-1, keepdim=True)).numpy()
    def __call__(self, wins):
        with self.torch.no_grad():
            a = self.p(audios=[w for w in wins], sampling_rate=48000, return_tensors="pt")
            ae = self.m.get_audio_features(**a).numpy()
        ae = ae / np.linalg.norm(ae, axis=1, keepdims=True)
        sims = ae @ self.text.T * 100.0
        return sims, ae


def run(root, name, out, eat_repo=None):
    model = {"yamnet": YAMNet, "panns": PANNs, "clap": CLAP}.get(name)
    t0 = time.time()
    model = EfficientAT(eat_repo) if name == "efficientat" else model()
    load_s = time.time() - t0
    meta = load_clips(root)
    res = {}
    audio_s = 0.0; infer_s = 0.0
    for k, c in enumerate(meta["clips"]):
        x, sr = read_wav(os.path.join(root, c["file"]))
        x = resample(x, sr, model.sr)
        starts, wins = windows(x, model.sr)
        t = time.time()
        scores, emb = model(wins)
        infer_s += time.time() - t; audio_s += len(x) / model.sr
        if name == "clap":
            nI = len(INSTRUMENTS)
            sims = scores[:, :nI]
            p = np.exp(sims - sims.max(1, keepdims=True)); p /= p.sum(1, keepdims=True)
            inst = p
            fam = np.stack([inst[:, [i for i, n in enumerate(INSTRUMENTS) if FAM_OF[n] == f]].sum(1) for f in FAMILIES], 1)
            src_s = scores[:, nI:]; q = np.exp(src_s - src_s.max(1, keepdims=True)); q /= q.sum(1, keepdims=True)
            src = q   # acoustic, electronic, imitation
        else:
            inst, fam, src = map_scores(model.labels, scores, INSTRUMENTS, FAMILIES)
        res[c["file"]] = {"starts": np.array(starts, np.float32), "inst": inst.astype(np.float16), "fam": fam.astype(np.float16),
                          "src": src.astype(np.float16), "emb": emb.astype(np.float16)}
        if k % 100 == 0:
            print(f"EMBED {name} {k}/{len(meta['clips'])}", flush=True)
    os.makedirs(out, exist_ok=True)
    flat = {}
    for i, (f, d) in enumerate(res.items()):
        for key, v in d.items():
            flat[f"{i}|{key}"] = v
    np.savez_compressed(os.path.join(out, f"{name}.npz"), files=np.array(list(res.keys())), **flat)
    info = {"model": name, "params": model.params, "load_s": round(load_s, 1), "audio_s": round(audio_s, 1), "infer_s": round(infer_s, 1),
            "s_per_audio_min": round(infer_s / max(1e-6, audio_s) * 60, 2), "window_s": WIN,
            "source_classes": ["acoustic", "electronic", "imitation"] if name == "clap" else ["acoustic", "electronic"]}
    json.dump(info, open(os.path.join(out, f"{name}.json"), "w"), indent=1)
    print("EMBED done", json.dumps(info))


if __name__ == "__main__":
    a = sys.argv
    run(a[1], a[2], a[3], a[a.index("--eat") + 1] if "--eat" in a else None)
