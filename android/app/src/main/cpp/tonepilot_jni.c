// JNI + AAudio glue between the Kotlin app and the Swift core (libTonePilotBridge.so).
// Audio: one low-latency AAudio output stream whose callback calls tp_render. When the output
// device changes (hub or cable plugged in/out) AAudio disconnects the stream; it is reopened on
// a helper thread at the same sample rate so the engine keeps running.
#include <jni.h>
#include <aaudio/AAudio.h>
#include <android/log.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define TAG "TonePilot"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// Swift (TonePilotBridge/CAPI.swift)
extern int32_t tp_init(const char *root, double sampleRate);
extern char *tp_last_error(void);
extern void tp_render(float *left, float *right, int32_t frames);
extern void tp_midi(const uint8_t *bytes, int32_t count);
extern char *tp_call(const char *request);
extern void tp_free(char *p);
extern void tp_pcm_append(const char *key, const float *samples, int32_t count);
extern void tp_listen_append(const float *samples, int32_t count, double sampleRate);

#define BLOCK 1024
static float scratchL[BLOCK], scratchR[BLOCK];
static AAudioStream *stream = NULL;
static int32_t streamRate = 48000;
static atomic_int ready = 0;
static atomic_int restarting = 0;
static pthread_mutex_t streamLock = PTHREAD_MUTEX_INITIALIZER;
static char lastAudioError[256] = "";

static aaudio_data_callback_result_t dataCallback(AAudioStream *s, void *user, void *audioData, int32_t numFrames) {
    (void)s; (void)user;
    float *out = (float *)audioData;
    if (!atomic_load(&ready)) {
        memset(out, 0, sizeof(float) * 2 * (size_t)numFrames);
        return AAUDIO_CALLBACK_RESULT_CONTINUE;
    }
    int32_t done = 0;
    while (done < numFrames) {
        int32_t n = numFrames - done;
        if (n > BLOCK) n = BLOCK;
        tp_render(scratchL, scratchR, n);
        float *o = out + 2 * done;
        for (int32_t i = 0; i < n; i++) { o[2 * i] = scratchL[i]; o[2 * i + 1] = scratchR[i]; }
        done += n;
    }
    return AAUDIO_CALLBACK_RESULT_CONTINUE;
}

static void errorCallback(AAudioStream *s, void *user, aaudio_result_t error);

static int openStream(int32_t sampleRate) {
    AAudioStreamBuilder *b = NULL;
    aaudio_result_t r = AAudio_createStreamBuilder(&b);
    if (r != AAUDIO_OK) { snprintf(lastAudioError, sizeof lastAudioError, "AAudio builder: %s", AAudio_convertResultToText(r)); return 0; }
    AAudioStreamBuilder_setDirection(b, AAUDIO_DIRECTION_OUTPUT);
    AAudioStreamBuilder_setPerformanceMode(b, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    AAudioStreamBuilder_setSharingMode(b, AAUDIO_SHARING_MODE_EXCLUSIVE);
    AAudioStreamBuilder_setFormat(b, AAUDIO_FORMAT_PCM_FLOAT);
    AAudioStreamBuilder_setChannelCount(b, 2);
    AAudioStreamBuilder_setUsage(b, AAUDIO_USAGE_MEDIA);
    AAudioStreamBuilder_setContentType(b, AAUDIO_CONTENT_TYPE_MUSIC);
    if (sampleRate > 0) AAudioStreamBuilder_setSampleRate(b, sampleRate);
    AAudioStreamBuilder_setDataCallback(b, dataCallback, NULL);
    AAudioStreamBuilder_setErrorCallback(b, errorCallback, NULL);
    AAudioStream *s = NULL;
    r = AAudioStreamBuilder_openStream(b, &s);
    if (r != AAUDIO_OK) {
        // Some devices refuse exclusive mode; shared still works with a little more latency.
        AAudioStreamBuilder_setSharingMode(b, AAUDIO_SHARING_MODE_SHARED);
        r = AAudioStreamBuilder_openStream(b, &s);
    }
    AAudioStreamBuilder_delete(b);
    if (r != AAUDIO_OK) { snprintf(lastAudioError, sizeof lastAudioError, "AAudio open: %s", AAudio_convertResultToText(r)); return 0; }
    // Double-buffer at the burst size: lowest latency that rarely glitches.
    int32_t burst = AAudioStream_getFramesPerBurst(s);
    if (burst > 0) AAudioStream_setBufferSizeInFrames(s, burst * 2);
    streamRate = AAudioStream_getSampleRate(s);
    r = AAudioStream_requestStart(s);
    if (r != AAUDIO_OK) {
        snprintf(lastAudioError, sizeof lastAudioError, "AAudio start: %s", AAudio_convertResultToText(r));
        AAudioStream_close(s);
        return 0;
    }
    stream = s;
    lastAudioError[0] = 0;
    LOGI("audio stream open: %d Hz, burst %d, %s", streamRate, burst,
         AAudioStream_getSharingMode(s) == AAUDIO_SHARING_MODE_EXCLUSIVE ? "exclusive" : "shared");
    return 1;
}

static void *restartThread(void *arg) {
    (void)arg;
    pthread_mutex_lock(&streamLock);
    if (stream) { AAudioStream_requestStop(stream); AAudioStream_close(stream); stream = NULL; }
    for (int attempt = 0; attempt < 20 && !openStream(streamRate); attempt++) usleep(250 * 1000);
    pthread_mutex_unlock(&streamLock);
    atomic_store(&restarting, 0);
    return NULL;
}

static void errorCallback(AAudioStream *s, void *user, aaudio_result_t error) {
    (void)s; (void)user;
    LOGE("audio stream error %s; reopening", AAudio_convertResultToText(error));
    if (error != AAUDIO_ERROR_DISCONNECTED) return;
    int expected = 0;
    if (!atomic_compare_exchange_strong(&restarting, &expected, 1)) return;
    pthread_t t;
    if (pthread_create(&t, NULL, restartThread, NULL) == 0) pthread_detach(t); else atomic_store(&restarting, 0);
}

#define FN(name) Java_com_tonepilot_app_NativeBridge_##name

JNIEXPORT jstring JNICALL FN(start)(JNIEnv *env, jclass cls, jstring root) {
    (void)cls;
    pthread_mutex_lock(&streamLock);
    int opened = stream != NULL || openStream(0);
    pthread_mutex_unlock(&streamLock);
    const char *path = (*env)->GetStringUTFChars(env, root, NULL);
    int32_t ok = tp_init(path, (double)streamRate);
    (*env)->ReleaseStringUTFChars(env, root, path);
    if (!ok) {
        char *e = tp_last_error();
        jstring msg = (*env)->NewStringUTF(env, e ? e : "Start failed");
        tp_free(e);
        return msg;
    }
    atomic_store(&ready, 1);
    return (*env)->NewStringUTF(env, opened ? "" : lastAudioError);
}

JNIEXPORT jstring JNICALL FN(audioStatus)(JNIEnv *env, jclass cls) {
    (void)cls;
    char buf[320];
    pthread_mutex_lock(&streamLock);
    if (stream) {
        int32_t burst = AAudioStream_getFramesPerBurst(stream);
        int32_t size = AAudioStream_getBufferSizeInFrames(stream);
        snprintf(buf, sizeof buf, "%d Hz · buffer %d frames (≈%.1f ms) · %s · device %d", streamRate, size,
                 1000.0 * size / (streamRate > 0 ? streamRate : 48000),
                 AAudioStream_getSharingMode(stream) == AAUDIO_SHARING_MODE_EXCLUSIVE ? "exclusive" : "shared",
                 AAudioStream_getDeviceId(stream));
        (void)burst;
    } else {
        snprintf(buf, sizeof buf, "Audio output not running %s", lastAudioError);
    }
    pthread_mutex_unlock(&streamLock);
    return (*env)->NewStringUTF(env, buf);
}

JNIEXPORT void JNICALL FN(restartAudio)(JNIEnv *env, jclass cls) {
    (void)env; (void)cls;
    int expected = 0;
    if (!atomic_compare_exchange_strong(&restarting, &expected, 1)) return;
    pthread_t t;
    if (pthread_create(&t, NULL, restartThread, NULL) == 0) pthread_detach(t); else atomic_store(&restarting, 0);
}

JNIEXPORT void JNICALL FN(midi)(JNIEnv *env, jclass cls, jbyteArray data, jint offset, jint count) {
    (void)cls;
    if (count <= 0 || count > 4096) return;
    uint8_t buf[4096];
    (*env)->GetByteArrayRegion(env, data, offset, count, (jbyte *)buf);
    tp_midi(buf, count);
}

JNIEXPORT jstring JNICALL FN(call)(JNIEnv *env, jclass cls, jstring request) {
    (void)cls;
    const char *req = (*env)->GetStringUTFChars(env, request, NULL);
    char *res = tp_call(req);
    (*env)->ReleaseStringUTFChars(env, request, req);
    jstring out = (*env)->NewStringUTF(env, res ? res : "{}");
    tp_free(res);
    return out;
}

JNIEXPORT void JNICALL FN(pcmAppend)(JNIEnv *env, jclass cls, jstring key, jfloatArray samples, jint count) {
    (void)cls;
    const char *k = (*env)->GetStringUTFChars(env, key, NULL);
    float *p = (*env)->GetFloatArrayElements(env, samples, NULL);
    tp_pcm_append(k, p, count);
    (*env)->ReleaseFloatArrayElements(env, samples, p, JNI_ABORT);
    (*env)->ReleaseStringUTFChars(env, key, k);
}

JNIEXPORT void JNICALL FN(listenAppend)(JNIEnv *env, jclass cls, jfloatArray samples, jint count, jdouble sampleRate) {
    (void)cls;
    float *p = (*env)->GetFloatArrayElements(env, samples, NULL);
    tp_listen_append(p, count, sampleRate);
    (*env)->ReleaseFloatArrayElements(env, samples, p, JNI_ABORT);
}
