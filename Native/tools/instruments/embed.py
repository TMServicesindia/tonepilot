"""Per-window outputs of one pretrained model for every clip (research only, CI).
Saves <out>/<model>.npz with, per clip: window starts, mapped taxonomy scores (approach A) and
embeddings (input to approach C), plus timing and model-size facts.
Usage: embed.py <render dir> <model: yamnet|efficientat|panns|panns10|clap> <out dir> [--eat <EfficientAT repo>]"""
import json, os, sys, time
import numpy as np
from common import taxonomy, map_scores, read_wav, resample, windows, load_clips, WIN, HOP, MODEL_WINDOWS

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


class PANNsCNN10:
    """PANNs CNN10 (Kong et al. 2020; code MIT, weights CC BY 4.0, Zenodo 3987831): 5.2 M params,
    the same size class as EfficientAT mn10. Architecture as in audioset_tagging_cnn/pytorch/models.py."""
    sr = 32000
    URL = "https://zenodo.org/record/3987831/files/Cnn10_mAP%3D0.380.pth?download=1"
    def __init__(self, ckpt="/tmp/Cnn10_mAP=0.380.pth"):
        import torch, torch.nn as nn, torch.nn.functional as F, hashlib, urllib.request
        from torchlibrosa.stft import Spectrogram, LogmelFilterBank
        from panns_inference import labels
        self.torch = torch
        if not os.path.exists(ckpt):
            urllib.request.urlretrieve(self.URL, ckpt)
        self.sha256 = hashlib.sha256(open(ckpt, "rb").read()).hexdigest()
        class ConvBlock(nn.Module):
            def __init__(s, i, o):
                super().__init__()
                s.conv1 = nn.Conv2d(i, o, 3, 1, 1, bias=False); s.conv2 = nn.Conv2d(o, o, 3, 1, 1, bias=False)
                s.bn1 = nn.BatchNorm2d(o); s.bn2 = nn.BatchNorm2d(o)
            def forward(s, x):
                x = F.relu_(s.bn1(s.conv1(x))); x = F.relu_(s.bn2(s.conv2(x)))
                return F.avg_pool2d(x, kernel_size=(2, 2))
        class Cnn10(nn.Module):
            def __init__(s):
                super().__init__()
                s.spectrogram_extractor = Spectrogram(n_fft=1024, hop_length=320, win_length=1024, window="hann", center=True,
                                                      pad_mode="reflect", freeze_parameters=True)
                s.logmel_extractor = LogmelFilterBank(sr=32000, n_fft=1024, n_mels=64, fmin=50, fmax=14000, ref=1.0, amin=1e-10,
                                                      top_db=None, freeze_parameters=True)
                s.bn0 = nn.BatchNorm2d(64)
                s.conv_block1 = ConvBlock(1, 64); s.conv_block2 = ConvBlock(64, 128)
                s.conv_block3 = ConvBlock(128, 256); s.conv_block4 = ConvBlock(256, 512)
                s.fc1 = nn.Linear(512, 512); s.fc_audioset = nn.Linear(512, 527)
            def forward(s, x):
                x = s.logmel_extractor(s.spectrogram_extractor(x))
                x = s.bn0(x.transpose(1, 3)).transpose(1, 3)
                for b in (s.conv_block1, s.conv_block2, s.conv_block3, s.conv_block4):
                    x = b(x)
                x = torch.mean(x, dim=3)
                x = torch.max(x, dim=2)[0] + torch.mean(x, dim=2)
                emb = F.relu_(s.fc1(x))
                return torch.sigmoid(s.fc_audioset(emb)), emb
        self.m = Cnn10().eval()
        state = torch.load(ckpt, map_location="cpu")
        state = state.get("model", state)
        missing, unexpected = self.m.load_state_dict(state, strict=False)
        missing = [k for k in missing if not k.startswith(("spectrogram_extractor", "logmel_extractor"))]
        if missing:
            raise RuntimeError(f"CNN10 checkpoint is missing weights: {missing[:5]}")
        print(f"CNN10 checkpoint sha256 {self.sha256}; unexpected keys ignored: {len(unexpected)}", flush=True)
        self.labels = list(labels)
        self.params = int(sum(p.numel() for p in self.m.parameters()))
    def __call__(self, wins):
        with self.torch.no_grad():
            clip, emb = self.m(self.torch.from_numpy(np.stack(wins).astype(np.float32)))
            return clip.numpy(), emb.numpy()


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
    model = {"yamnet": YAMNet, "panns": PANNs, "panns10": PANNsCNN10, "clap": CLAP}.get(name)
    t0 = time.time()
    model = EfficientAT(eat_repo) if name == "efficientat" else model()
    load_s = time.time() - t0
    meta = load_clips(root)
    res = {}
    audio_s = 0.0; infer_s = 0.0
    for k, c in enumerate(meta["clips"]):
        x, sr = read_wav(os.path.join(root, c["file"]))
        x = resample(x, sr, model.sr)
        mw, mh = MODEL_WINDOWS.get(name, (WIN, HOP))
        starts, wins = windows(x, model.sr, mw, mh)
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
    info = {"model": name, "params": model.params, "weights_sha256": getattr(model, "sha256", None), "load_s": round(load_s, 1), "audio_s": round(audio_s, 1), "infer_s": round(infer_s, 1),
            "s_per_audio_min": round(infer_s / max(1e-6, audio_s) * 60, 2), "window_s": MODEL_WINDOWS.get(name, (WIN, HOP))[0],
            "source_classes": ["acoustic", "electronic", "imitation"] if name == "clap" else ["acoustic", "electronic"]}
    json.dump(info, open(os.path.join(out, f"{name}.json"), "w"), indent=1)
    print("EMBED done", json.dumps(info))


if __name__ == "__main__":
    a = sys.argv
    run(a[1], a[2], a[3], a[a.index("--eat") + 1] if "--eat" in a else None)
