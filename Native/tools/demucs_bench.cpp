// Benchmark + sanity check for the on-device separator (run in CI on Apple Silicon).
// Synthesises 40 s of music from four known parts, separates it with N parallel blocks the same
// way the app does, and reports speed and how much of each part lands in the right stem.
#include "tp_demucs.h"
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <thread>
#include <vector>

static const int SR = 44100;

int main(int argc, char **argv) {
    if (argc < 2) { std::fprintf(stderr, "usage: %s model.bin [threads] [seconds]\n", argv[0]); return 1; }
    int threads = argc > 2 ? std::atoi(argv[2]) : 3;
    double seconds = argc > 3 ? std::atof(argv[3]) : 40;
    long n = (long)(seconds * SR);
    // Parts: 0 drums, 1 bass, 2 other (chords), 3 vocals — the model's output order.
    std::vector<std::vector<float>> parts(4, std::vector<float>(n, 0));
    std::mt19937 rng(1);
    std::normal_distribution<float> noise(0, 1);
    double beat = 0.5;
    for (long i = 0; i < n; ++i) {
        double t = (double)i / SR, tb = std::fmod(t, beat);
        // Kick + hat: decaying low sine and noise burst on every beat.
        parts[0][i] = 0.6f * (float)(std::sin(2 * M_PI * 55 * tb) * std::exp(-tb * 18)) + 0.15f * noise(rng) * (float)std::exp(-tb * 60);
        int bar = (int)(t / 2) % 4;
        const double roots[4] = {65.41, 55.0, 43.65, 49.0};   // C2 A1 F1 G1
        parts[1][i] = 0.35f * (float)std::sin(2 * M_PI * roots[bar] * t);
        const double chord[4][3] = {{261.6, 329.6, 392.0}, {220.0, 261.6, 329.6}, {174.6, 220.0, 261.6}, {196.0, 246.9, 293.7}};
        for (int k = 0; k < 3; ++k) parts[2][i] += 0.08f * (float)(std::sin(2 * M_PI * chord[bar][k] * t) + 0.3 * std::sin(4 * M_PI * chord[bar][k] * t));
        // Voice: vibrato tone with harmonics, phrases on/off.
        if (std::fmod(t, 4.0) < 3.0) {
            double f = 440 * std::pow(2.0, ((int)(t * 2) % 5) / 12.0) * (1 + 0.01 * std::sin(2 * M_PI * 5.5 * t));
            for (int h = 1; h <= 6; ++h) parts[3][i] += 0.12f / h * (float)std::sin(2 * M_PI * f * h * t);
        }
    }
    std::vector<float> mixL(n), mixR(n);
    for (long i = 0; i < n; ++i) { float m = parts[0][i] + parts[1][i] + parts[2][i] + parts[3][i]; mixL[i] = m; mixR[i] = m; }

    auto t0 = std::chrono::steady_clock::now();
    tp_demucs *model = tp_demucs_load(argv[1]);
    if (!model) { std::fprintf(stderr, "model failed to load\n"); return 2; }
    auto t1 = std::chrono::steady_clock::now();
    int sources = tp_demucs_source_count(model);
    long block = (n + threads - 1) / threads;
    std::vector<std::vector<float>> outs(threads);
    std::vector<std::thread> pool;
    for (int k = 0; k < threads; ++k) {
        pool.emplace_back([&, k] {
            long start = k * block, len = std::min(block, n - start);
            outs[k].resize((size_t)sources * 2 * len);
            tp_demucs_separate(model, mixL.data() + start, mixR.data() + start, len, outs[k].data(), nullptr, nullptr);
        });
    }
    for (auto &t : pool) t.join();
    auto t2 = std::chrono::steady_clock::now();
    double load = std::chrono::duration<double>(t1 - t0).count(), sep = std::chrono::duration<double>(t2 - t1).count();
    std::printf("RESULT load %.1f s, separate %.1f s for %.0f s of audio with %d threads = %.2f× real time\n",
                load, sep, seconds, threads, sep / seconds);
    // Energy of each true part found in each stem (correlation of stem with part).
    const char *names[4] = {"drums", "bass", "other", "vocals"};
    int correct = 0;
    for (int p = 0; p < 4; ++p) {
        double best = -1; int bestStem = -1;
        std::printf("part %-6s:", names[p]);
        for (int s = 0; s < 4; ++s) {
            double dot = 0, a = 0, b = 0;
            for (int k = 0; k < threads; ++k) {
                long start = k * block, len = std::min(block, n - start);
                const float *stem = outs[k].data() + (long)s * 2 * len;
                for (long i = 0; i < len; ++i) { dot += stem[i] * parts[p][start + i]; a += stem[i] * stem[i]; b += parts[p][start + i] * parts[p][start + i]; }
            }
            double corr = dot / std::sqrt(a * b + 1e-12);
            std::printf(" %s=%.2f", names[s], corr);
            if (corr > best) { best = corr; bestStem = s; }
        }
        std::printf("\n");
        if (bestStem == p) ++correct;
    }
    std::printf("RESULT %d/4 parts land in the right stem\n", correct);
    tp_demucs_free(model);
    return correct >= 3 ? 0 : 3;
}
