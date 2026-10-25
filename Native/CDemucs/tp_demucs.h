// C interface to demucs.cpp (MIT, github.com/sevagh/demucs.cpp) for on-device stem separation.
// Demucs v4 hybrid transformer (htdemucs, MIT, Meta AI) splits music into drums, bass, other
// and vocals. Audio is 44.1 kHz stereo, planar float.
#ifndef TP_DEMUCS_H
#define TP_DEMUCS_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct tp_demucs tp_demucs;

/// Loads ggml weights (e.g. ggml-model-htdemucs-4s-f16.bin). Returns NULL on failure.
tp_demucs *tp_demucs_load(const char *model_path);
void tp_demucs_free(tp_demucs *model);

/// 4 (drums, bass, other, vocals) or 6 (… guitar, piano).
int tp_demucs_source_count(const tp_demucs *model);

typedef void (*tp_demucs_progress)(void *context, float progress);

/// Separates one block (single thread; call from several threads for parallel blocks — the
/// model is read-only). `out` holds sources × 2 × frames floats: [source][channel][frame].
/// Returns 0 on success.
int tp_demucs_separate(const tp_demucs *model, const float *left, const float *right, long frames,
                       float *out, tp_demucs_progress progress, void *context);

#ifdef __cplusplus
}
#endif
#endif
