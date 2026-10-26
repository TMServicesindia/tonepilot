#include "tp_demucs.h"
#include "model.hpp"
#include "tp_network_hook.hpp"
#include <atomic>
#include <vector>
#include <Eigen/Dense>
#include <memory>
#include <string>
#include <cstdio>
#include <cstdlib>

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

// Diagnostics: with TP_DUMP_NET=<dir>, the first segment's network inputs and outputs are written
// (row-major float32) for each engine, so CI can check both against PyTorch.
static void dump(const char *name, const std::vector<float> &v) {
    const char *dir = std::getenv("TP_DUMP_NET");
    if (!dir) return;
    std::string path = std::string(dir) + "/" + name;
    if (FILE *f = std::fopen(path.c_str(), "wb")) { std::fwrite(v.data(), sizeof(float), v.size(), f); std::fclose(f); }
}
static std::atomic<bool> g_dumped_cpu{false}, g_dumped_ml{false};

static std::vector<float> row_major(const Eigen::Tensor3dXf &t, int c0) {
    // (c, f, t) tensor → [c][f][t]; for the time branch (1, c, l) use c0 = 1.
    const int C = (int)t.dimension(c0), F = c0 == 0 ? (int)t.dimension(1) : 1, T = (int)t.dimension(2);
    std::vector<float> v((size_t)C * F * T);
    for (int k = 0; k < T; ++k)
        for (int f = 0; f < F; ++f)
            for (int c = 0; c < C; ++c) v[((size_t)c * F + f) * T + k] = c0 == 0 ? t(c, f, k) : t(0, c, k);
    return v;
}

void tp::after_cpu_network(demucscpp::demucs_segment_buffers &b) {
    if (!std::getenv("TP_DUMP_NET") || g_dumped_cpu.exchange(true)) return;
    dump("cpu_x_out.f32", row_major(b.x_out, 0));
    dump("cpu_xt_out.f32", row_major(b.xt_out, 1));
}

bool tp::run_network(demucscpp::demucs_segment_buffers &b, int nb_sources) {
    tp_demucs_network network = g_network;
    if (std::getenv("TP_DUMP_NET") && !network && !g_dumped_cpu.load()) {
        dump("cpu_x.f32", row_major(b.x, 0));
        dump("cpu_xt.f32", row_major(b.xt, 1));
    }
    if (!network || (nb_sources != 4 && nb_sources != 6)) return false;
    const int C = (int)b.x.dimension(0), F = (int)b.x.dimension(1), T = (int)b.x.dimension(2);
    const int L = (int)b.xt.dimension(2);
    const int S = nb_sources;
    if (C != 4 || b.x_out.dimension(0) != 4 * S || b.xt_out.dimension(1) != 2 * S) return false;
    // Eigen tensors are column-major: (c, f, t) is at c + C * (f + F * t). Core ML wants row-major.
    std::vector<float> x((size_t)C * F * T), xt((size_t)2 * L), x_out((size_t)4 * S * F * T), xt_out((size_t)2 * S * L);
    for (int t = 0; t < T; ++t)
        for (int f = 0; f < F; ++f)
            for (int c = 0; c < C; ++c) x[((size_t)c * F + f) * T + t] = b.x(c, f, t);
    for (int l = 0; l < L; ++l)
        for (int c = 0; c < 2; ++c) xt[(size_t)c * L + l] = b.xt(0, c, l);
    const bool dumping = std::getenv("TP_DUMP_NET") && !g_dumped_ml.exchange(true);
    if (dumping) { dump("ml_x.f32", x); dump("ml_xt.f32", xt); }
    if (network(g_network_context, x.data(), xt.data(), x_out.data(), xt_out.data(), F, T, L) != 0) return false;
    if (dumping) {
        dump("ml_x_out.f32", x_out); dump("ml_xt_out.f32", xt_out);
        dump("ml_x_after.f32", x);  // must equal ml_x: the network may not change its inputs
    }
    for (int t = 0; t < T; ++t)
        for (int f = 0; f < F; ++f)
            for (int c = 0; c < 4 * S; ++c) b.x_out(c, f, t) = x_out[((size_t)c * F + f) * T + t];
    for (int l = 0; l < L; ++l)
        for (int c = 0; c < 2 * S; ++c) b.xt_out(0, c, l) = xt_out[(size_t)c * L + l];
    return true;
}
