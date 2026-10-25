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
