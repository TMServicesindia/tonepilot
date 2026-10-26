#!/usr/bin/env python3
"""Applies TonePilot's speed-ups to demucs.cpp sources (idempotent).

conv.hpp: the transposed convolutions are replaced by a direct method (conv_tr_fast.inc) that
gives the same sums without a zero-stuffed matrix. Build with -DTP_DEMUCS_REFERENCE to use the
original code (CI compares both on the same audio)."""
import pathlib, sys
src = pathlib.Path(__file__).parent / "demucs" / "src"
conv = src / "conv.hpp"
s = conv.read_text()
if "conv_tr_fast.inc" not in s:
    s = s.replace("Eigen::Tensor3dXf conv2d_tr(const", "Eigen::Tensor3dXf conv2d_tr_reference(const", 1)
    s = s.replace("Eigen::Tensor3dXf conv2d_tr_fused_gelu(const", "Eigen::Tensor3dXf conv2d_tr_fused_gelu_reference(const", 1)
    marker = "template <int in_channels, int out_channels, int kernel_size, int stride,\n          int pad, int dilation>\nEigen::Tensor3dXf conv1d_tr("
    assert marker in s, "conv1d_tr not found"
    s = s.replace(marker, '#include "conv_tr_fast.inc"\n\n' + marker, 1)
    assert "conv2d_tr_reference" in s and "conv2d_tr_fused_gelu_reference" in s
    conv.write_text(s)
    print("patched conv.hpp")
else:
    print("conv.hpp already patched")

inf = src / "model_inference.cpp"
s = inf.read_text()
if "tp::run_network" not in s:
    s = s.replace('#include "crosstransformer.hpp"', '#include "crosstransformer.hpp"\n#include "tp_network_hook.hpp"', 1)
    start = 'cb(current_progress + 0.0f, "Time branch: normalized");'
    end = 'cb(current_progress + segment_progress, "Mask + istft");'
    assert s.count(start) >= 1 and s.count(end) >= 1
    i = s.index(start) + len(start)
    s = s[:i] + "\n\n    // TonePilot: Core ML runs the network when available.\n    if (!tp::run_network(buffers, model.is_4sources ? 4 : 6))\n    {" + s[i:]
    j = s.index(end, i)
    s = s[:j] + "}\n\n    " + s[j:]
    inf.write_text(s)
    print("patched model_inference.cpp")
else:
    print("model_inference.cpp already patched")
