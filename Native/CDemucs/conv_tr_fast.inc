// Included inside namespace demucscpp by Native/patch-demucs.py (TonePilot).
//
// Transposed 2-D convolution computed directly: one GEMM per kernel tap, scattered into the
// output — instead of building a zero-stuffed im2col matrix (stride× larger, mostly zeros) and
// multiplying all of it. The sums are exactly the reference's (only their order differs), so
// results match to float rounding, with ~stride× fewer multiply-adds and far less memory.
template <int in_channels, int out_channels, int kernel_height, int kernel_width, int stride_height,
          int stride_width, int pad_height, int pad_width, int dilation_height, int dilation_width,
          bool fuse_gelu>
Eigen::Tensor3dXf conv2d_tr_direct(const Eigen::Tensor3dXf &x, const Eigen::Tensor4dXf &w,
                                   const Eigen::Tensor1dXf &b)
{
    const int C = x.dimension(0), H = x.dimension(1), W = x.dimension(2);
    const int ekh = kernel_height + (kernel_height - 1) * (dilation_height - 1);
    const int ekw = kernel_width + (kernel_width - 1) * (dilation_width - 1);
    const int EH = (H - 1) * stride_height + ekh, EW = (W - 1) * stride_width + ekw;
    const int out_h = EH - 2 * pad_height, out_w = EW - 2 * pad_width;
    const long R = (long)out_h * out_w;

    Eigen::MatrixXf acc(out_channels, R);
    for (int co = 0; co < out_channels; ++co) acc.row(co).setConstant(b(co));

    // x is (C, H, W) column-major: column q = h + H * w of a C × (H·W) matrix.
    Eigen::Map<const Eigen::MatrixXf> X(x.data(), C, (long)H * W);
    Eigen::MatrixXf Y(out_channels, (long)H * W);
    for (int kw = 0; kw < kernel_width; ++kw) {
        for (int kh = 0; kh < kernel_height; ++kh) {
            // w is (Cin, Cout, Kh, Kw): each (kh, kw) slice is a contiguous Cin × Cout block.
            const float *wk = w.data() + (long)in_channels * out_channels * (kh + (long)kernel_height * kw);
            Eigen::Map<const Eigen::MatrixXf> Wk(wk, in_channels, out_channels);
            Y.noalias() = Wk.transpose() * X;
            for (int ww = 0; ww < W; ++ww) {
                const int ew = ww * stride_width + kw * dilation_width - pad_width;
                if (ew < 0 || ew >= EW) continue;
                for (int hh = 0; hh < H; ++hh) {
                    const int eh = hh * stride_height + kh * dilation_height - pad_height;
                    if (eh < 0 || eh >= EH) continue;
                    const long r = (long)eh * EW + ew; // same row indexing as the reference
                    if (r >= R) continue;
                    acc.col(r) += Y.col(hh + (long)H * ww);
                }
            }
        }
    }

    Eigen::Tensor3dXf y_out(out_channels, out_h, out_w);
    for (int co = 0; co < out_channels; ++co)
        for (int ho = 0; ho < out_h; ++ho)
            for (int wo = 0; wo < out_w; ++wo) {
                float v = acc(co, (long)ho * out_w + wo);
                if (fuse_gelu) v = 0.5f * v * (1.0f + std::erf(v / std::sqrt(2.0f)));
                y_out(co, ho, wo) = v;
            }
    return y_out;
}

template <int in_channels, int out_channels, int kernel_height, int kernel_width, int stride_height,
          int stride_width, int pad_height, int pad_width, int dilation_height, int dilation_width>
Eigen::Tensor3dXf conv2d_tr(const Eigen::Tensor3dXf &x, const Eigen::Tensor4dXf &w, const Eigen::Tensor1dXf &b)
{
#ifdef TP_DEMUCS_REFERENCE
    return conv2d_tr_reference<in_channels, out_channels, kernel_height, kernel_width, stride_height, stride_width,
                               pad_height, pad_width, dilation_height, dilation_width>(x, w, b);
#else
    return conv2d_tr_direct<in_channels, out_channels, kernel_height, kernel_width, stride_height, stride_width,
                            pad_height, pad_width, dilation_height, dilation_width, false>(x, w, b);
#endif
}

template <int in_channels, int out_channels, int kernel_height, int kernel_width, int stride_height,
          int stride_width, int pad_height, int pad_width, int dilation_height, int dilation_width>
Eigen::Tensor3dXf conv2d_tr_fused_gelu(const Eigen::Tensor3dXf &x, const Eigen::Tensor4dXf &w, const Eigen::Tensor1dXf &b)
{
#ifdef TP_DEMUCS_REFERENCE
    return conv2d_tr_fused_gelu_reference<in_channels, out_channels, kernel_height, kernel_width, stride_height,
                                          stride_width, pad_height, pad_width, dilation_height, dilation_width>(x, w, b);
#else
    return conv2d_tr_direct<in_channels, out_channels, kernel_height, kernel_width, stride_height, stride_width,
                            pad_height, pad_width, dilation_height, dilation_width, true>(x, w, b);
#endif
}
