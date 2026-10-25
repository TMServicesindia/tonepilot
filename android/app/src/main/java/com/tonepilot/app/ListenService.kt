package com.tonepilot.app

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder

/**
 * Keeps the microphone available while you switch to YouTube/Spotify to play the song
 * (Android only allows background recording from a visible foreground service).
 * The audio goes into memory in the Swift core and is discarded after analysis.
 */
class ListenService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(NotificationManager::class.java)!!
        nm.createNotificationChannel(NotificationChannel("listen", "Listen Mode", NotificationManager.IMPORTANCE_LOW))
        val n = Notification.Builder(this, "listen")
            .setContentTitle("TonePilot is listening")
            .setContentText("Play the song from the start. Listening stops when it ends.")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        else startForeground(1, n)
        Recorder.start()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        Recorder.stop()
        super.onDestroy()
    }

    companion object {
        fun start(context: Context) = context.startForegroundService(Intent(context, ListenService::class.java))
        fun stop(context: Context) = context.stopService(Intent(context, ListenService::class.java))
    }

    /** Mono 44.1 kHz float capture fed to the core in ~100 ms blocks. */
    object Recorder {
        private const val RATE = 44100
        @Volatile private var running = false
        private var thread: Thread? = null
        @Volatile var error: String? = null

        @SuppressLint("MissingPermission")
        fun start() {
            if (running) return
            error = null
            running = true
            thread = Thread {
                val min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT)
                val size = maxOf(min, RATE / 2 * 4)
                fun open(source: Int): AudioRecord? {
                    val r = runCatching { AudioRecord(source, RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT, size) }.getOrNull()
                    if (r != null && r.state != AudioRecord.STATE_INITIALIZED) { r.release(); return null }
                    return r
                }
                // UNPROCESSED skips voice processing (noise suppression would eat the music) where supported.
                val rec = try {
                    open(MediaRecorder.AudioSource.UNPROCESSED) ?: open(MediaRecorder.AudioSource.MIC)
                        ?: AudioRecord(MediaRecorder.AudioSource.MIC, RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT, size)
                } catch (e: Exception) {
                    error = "The microphone couldn't be opened: ${e.message}"
                    running = false
                    return@Thread
                }
                if (rec.state != AudioRecord.STATE_INITIALIZED) {
                    error = "The microphone couldn't be opened."
                    running = false
                    rec.release()
                    return@Thread
                }
                val buf = FloatArray(RATE / 10)
                rec.startRecording()
                while (running) {
                    val n = rec.read(buf, 0, buf.size, AudioRecord.READ_BLOCKING)
                    if (n > 0) NativeBridge.listenAppend(buf, n, RATE.toDouble())
                }
                rec.stop()
                rec.release()
            }.apply { name = "TonePilot-listen"; start() }
        }

        fun stop() {
            running = false
            thread?.join(1000)
            thread = null
        }
    }
}
