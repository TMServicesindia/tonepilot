#include "tp_demucs.h"
#include "model.hpp"
#include "tp_network_hook.hpp"
#include <atomic>
#include <vector>
#include <Eigen/Dense>
#include <memory>
#include <string>

extern "C" void (*tp_demucs_debug_log)(const char *message) = nullptr;

struct tp_demucs {
    demucscpp::demucs_model model;
};

extern "C" tp_demucs *tp_demucs_load(const char *model_path) {
    auto m = std::make_unique<tp_demucs>();
    try {
        if (!demucscpp::load_demucs_model(std::string(model_path), &m->model)) return nullptr;
    } catch (...) {
        return nullptr;
    }
    return m.release();
}

extern "C" void tp_demucs_free(tp_demucs *model) { delete model; }

extern "C" int tp_demucs_source_count(const tp_demucs *model) { return model && model->model.is_4sources ? 4 : 6; }

extern "C" int tp_demucs_separate(const tp_demucs *model, const float *left, const float *right, long frames,
                                  float *out, tp_demucs_progress progress, void *context) {
    if (!model || !left || !right || !out || frames <= 0) return 1;
    try {
        Eigen::MatrixXf audio(2, frames);
        for (long i = 0; i < frames; ++i) { audio(0, i) = left[i]; audio(1, i) = right[i]; }
        demucscpp::ProgressCallback cb = [progress, context](float p, const std::string &message) {
            if (progress) progress(context, p);
            if (tp_demucs_debug_log) tp_demucs_debug_log(message.c_str());
        };
        Eigen::Tensor3dXf targets = demucscpp::demucs_inference(model->model, audio, cb);
        const int sources = tp_demucs_source_count(model);
        for (int s = 0; s < sources; ++s)
            for (int c = 0; c < 2; ++c) {
                float *dst = out + ((long)s * 2 + c) * frames;
                for (long i = 0; i < frames; ++i) dst[i] = targets(s, c, i);
            }
        return 0;
    } catch (...) {
        return 2;
    }
}

// MARK: External network (Core ML)

static std::atomic<tp_demucs_network> g_network{nullptr};
static std::atomic<void *> g_network_context{nullptr};

extern "C" void tp_demucs_set_network(tp_demucs_network network, void *context) {
    g_network_context = context;
    g_network = network;
}

bool tp::run_network(demucscpp::demucs_segment_buffers &b, int nb_sources) {
    tp_demucs_network network = g_network;
    if (!network || nb_sources != 4) return false;
    const int C = (int)b.x.dimension(0), F = (int)b.x.dimension(1), T = (int)b.x.dimension(2);
    const int L = (int)b.xt.dimension(2);
    if (C != 4 || b.x_out.dimension(0) != 16 || b.xt_out.dimension(1) != 8) return false;
    // Eigen tensors are column-major: (c, f, t) is at c + C * (f + F * t). Core ML wants row-major.
    std::vector<float> x((size_t)C * F * T), xt((size_t)2 * L), x_out((size_t)16 * F * T), xt_out((size_t)8 * L);
    for (int t = 0; t < T; ++t)
        for (int f = 0; f < F; ++f)
            for (int c = 0; c < C; ++c) x[((size_t)c * F + f) * T + t] = b.x(c, f, t);
    for (int l = 0; l < L; ++l)
        for (int c = 0; c < 2; ++c) xt[(size_t)c * L + l] = b.xt(0, c, l);
    if (network(g_network_context, x.data(), xt.data(), x_out.data(), xt_out.data(), F, T, L) != 0) return false;
    for (int t = 0; t < T; ++t)
        for (int f = 0; f < F; ++f)
            for (int c = 0; c < 16; ++c) b.x_out(c, f, t) = x_out[((size_t)c * F + f) * T + t];
    for (int l = 0; l < L; ++l)
        for (int c = 0; c < 8; ++c) b.xt_out(0, c, l) = xt_out[(size_t)c * L + l];
    return true;
}
