#include "tp_demucs.h"
#include "model.hpp"
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
