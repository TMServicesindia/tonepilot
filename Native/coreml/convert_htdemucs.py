#!/usr/bin/env python3
"""Converts the Demucs v4 (htdemucs, 4 sources) network to Core ML, so the iPhone can run it on
the GPU / Neural Engine instead of the CPU.

Only the network moves: the STFT, normalisation, segmenting and inverse STFT stay in
demucs.cpp (unchanged). So the Core ML model takes the *normalised* spectrogram (complex as
channels) and waveform of one 7.8 s segment, and returns the network outputs before
de-normalisation — exactly what demucs.cpp's model_inference computes between
"Time branch: normalized" and "Mask + istft".

Checks the converted model against PyTorch on the same input and writes HTDemucs.mlpackage.
"""
import sys, time
import numpy as np
import torch
from torch import nn
from einops import rearrange

torch.backends.mha.set_fastpath_enabled(False)  # plain ops that Core ML understands

from demucs.pretrained import get_model

bag = get_model("htdemucs")
m = bag.models[0] if hasattr(bag, "models") else bag
m.eval()
SEG = int(m.segment * m.samplerate)  # 343980 samples (7.8 s at 44.1 kHz)


class Core(nn.Module):
    """HTDemucs.forward between input normalisation and de-normalisation."""

    def __init__(self, model):
        super().__init__()
        self.m = model

    def forward(self, x, xt):
        m = self.m
        saved, saved_t, lengths, lengths_t = [], [], [], []
        for idx, encode in enumerate(m.encoder):
            lengths.append(x.shape[-1])
            inject = None
            if idx < len(m.tencoder):
                lengths_t.append(xt.shape[-1])
                tenc = m.tencoder[idx]
                xt = tenc(xt)
                if not tenc.empty:
                    saved_t.append(xt)
                else:
                    inject = xt
            x = encode(x, inject)
            if idx == 0 and m.freq_emb is not None:
                frs = torch.arange(x.shape[-2], device=x.device)
                emb = m.freq_emb(frs).t()[None, :, :, None].expand_as(x)
                x = x + m.freq_emb_scale * emb
            saved.append(x)
        if m.crosstransformer:
            if m.bottom_channels:
                b, c, f, t = x.shape
                x = rearrange(x, "b c f t-> b c (f t)")
                x = m.channel_upsampler(x)
                x = rearrange(x, "b c (f t)-> b c f t", f=f)
                xt = m.channel_upsampler_t(xt)
            x, xt = m.crosstransformer(x, xt)
            if m.bottom_channels:
                x = rearrange(x, "b c f t-> b c (f t)")
                x = m.channel_downsampler(x)
                x = rearrange(x, "b c (f t)-> b c f t", f=f)
                xt = m.channel_downsampler_t(xt)
        for idx, decode in enumerate(m.decoder):
            skip = saved.pop(-1)
            x, pre = decode(x, skip, lengths.pop(-1))
            offset = m.depth - len(m.tdecoder)
            if idx >= offset:
                tdec = m.tdecoder[idx - offset]
                length_t = lengths_t.pop(-1)
                if tdec.empty:
                    pre = pre[:, :, 0]
                    xt, _ = tdec(pre, None, length_t)
                else:
                    skip = saved_t.pop(-1)
                    xt, _ = tdec(xt, skip, length_t)
        return x, xt


def segment_inputs():
    """Real network inputs for one segment of a synthetic song (via PyTorch's own spec)."""
    sr = m.samplerate
    t = np.arange(SEG) / sr
    mix = 0.3 * np.sin(2 * np.pi * 110 * t) + 0.2 * np.sin(2 * np.pi * 440 * (1 + 0.01 * np.sin(2 * np.pi * 5 * t)) * t)
    mix += 0.2 * np.sign(np.sin(2 * np.pi * 2 * t)) * np.exp(-((t * 2) % 1) * 20) * np.random.RandomState(0).randn(SEG)
    mix = torch.tensor(np.stack([mix, mix * 0.9]), dtype=torch.float32)[None]
    with torch.no_grad():
        z = m._spec(mix)
        x = m._magnitude(z)
        x = (x - x.mean(dim=(1, 2, 3), keepdim=True)) / (1e-5 + x.std(dim=(1, 2, 3), keepdim=True))
        xt = (mix - mix.mean(dim=(1, 2), keepdim=True)) / (1e-5 + mix.std(dim=(1, 2), keepdim=True))
    return x, xt


def snr(ref, out):
    ref = ref.astype(np.float64); out = out.astype(np.float64)
    return 10 * np.log10(np.sum(ref ** 2) / max(np.sum((ref - out) ** 2), 1e-30))


if __name__ == "__main__":
    import coremltools as ct
    out_path = sys.argv[1] if len(sys.argv) > 1 else "HTDemucs.mlpackage"
    core = Core(m).eval()
    x, xt = segment_inputs()
    print("inputs", tuple(x.shape), tuple(xt.shape))
    with torch.no_grad():
        ref_x, ref_xt = core(x, xt)
        traced = torch.jit.trace(core, (x, xt), check_trace=False)
    print("outputs", tuple(ref_x.shape), tuple(ref_xt.shape))

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="x", shape=tuple(x.shape)), ct.TensorType(name="xt", shape=tuple(xt.shape))],
        outputs=[ct.TensorType(name="x_out"), ct.TensorType(name="xt_out")],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
    )
    mlmodel.short_description = "Demucs v4 htdemucs (4 sources) network core — Meta AI, MIT licence"
    mlmodel.save(out_path)
    print("saved", out_path)

    feed = {"x": x.numpy(), "xt": xt.numpy()}
    for units in ["CPU_AND_GPU", "CPU_AND_NE", "ALL", "CPU_ONLY"]:
        try:
            mm = ct.models.MLModel(out_path, compute_units=getattr(ct.ComputeUnit, units))
            mm.predict(feed)  # warm-up
            t0 = time.time(); r = mm.predict(feed); dt = time.time() - t0
            print(f"RESULT {units}: {dt:.2f} s per 7.8 s segment; "
                  f"x_out {snr(ref_x.numpy(), r['x_out']):.1f} dB, xt_out {snr(ref_xt.numpy(), r['xt_out']):.1f} dB vs PyTorch")
        except Exception as e:
            print(f"RESULT {units}: failed ({e})")
    with torch.no_grad():
        t0 = time.time(); core(x, xt); print(f"RESULT PyTorch CPU: {time.time() - t0:.2f} s per segment")
