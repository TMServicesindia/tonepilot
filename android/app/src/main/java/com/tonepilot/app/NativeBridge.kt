package com.tonepilot.app

import org.json.JSONArray
import org.json.JSONObject

/**
 * The Swift core (the same engine and analysis code as the iPhone app), reached through
 * tonepilot_jni.c. Commands are JSON: `call("""{"cmd":"state"}""")`.
 */
object NativeBridge {
    init {
        System.loadLibrary("c++_shared")
        System.loadLibrary("TonePilotBridge")
        System.loadLibrary("tonepilot_jni")
    }

    /** Opens the audio output and starts the core. Returns "" on success, else an error. */
    @JvmStatic external fun start(root: String): String
    @JvmStatic external fun audioStatus(): String
    @JvmStatic external fun restartAudio()
    @JvmStatic external fun midi(data: ByteArray, offset: Int, count: Int)
    @JvmStatic external fun call(request: String): String
    @JvmStatic external fun pcmAppend(key: String, samples: FloatArray, count: Int)
    @JvmStatic external fun listenAppend(samples: FloatArray, count: Int, sampleRate: Double)

    fun cmd(name: String, vararg args: Pair<String, Any?>): JSONObject {
        val req = JSONObject().put("cmd", name)
        for ((k, v) in args) req.put(k, v ?: JSONObject.NULL)
        return try {
            JSONObject(call(req.toString()))
        } catch (e: Exception) {
            JSONObject().put("error", e.message ?: "bad response")
        }
    }
}

fun JSONObject.str(key: String): String = optString(key, "")
fun JSONObject.objects(key: String): List<JSONObject> = optJSONArray(key).objects()
fun JSONObject.strings(key: String): List<String> {
    val a = optJSONArray(key) ?: return emptyList()
    return (0 until a.length()).map { a.optString(it) }
}
fun JSONArray?.objects(): List<JSONObject> {
    if (this == null) return emptyList()
    return (0 until length()).mapNotNull { optJSONObject(it) }
}

/** "1:05" */
fun Double.mmss(): String {
    val s = if (this < 0) 0 else this.toInt()
    return "%d:%02d".format(s / 60, s % 60)
}
