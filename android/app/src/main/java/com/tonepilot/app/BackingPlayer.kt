package com.tonepilot.app

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.PlaybackParams

/**
 * Plays the imported song (whole, or one section looped) so you can play along, and supplies the
 * song position that drives automatic tone switching. Practice speeds keep the pitch.
 */
class BackingPlayer {
    private var player: MediaPlayer? = null
    private var loadedPath: String? = null
    private var loopStart = 0.0
    private var loopEnd: Double? = null
    private var looping = false
    var rate = 1f
        private set

    val isPlaying: Boolean get() = runCatching { player?.isPlaying == true }.getOrDefault(false)

    /** Song position in seconds while playing, else null. */
    val position: Double? get() = if (isPlaying) player!!.currentPosition / 1000.0 else null

    fun play(path: String, from: Double, to: Double? = null, loop: Boolean = false, speed: Float = 1f, volume: Float = 1f) {
        val p = prepare(path) ?: return
        loopStart = from
        loopEnd = to
        looping = loop
        rate = speed
        p.setVolume(volume, volume)
        p.seekTo((from * 1000).toLong(), MediaPlayer.SEEK_CLOSEST)
        p.start()
        p.playbackParams = PlaybackParams().setSpeed(speed).setPitch(1f)
    }

    fun setVolume(volume: Float) { player?.setVolume(volume, volume) }

    /** Called every tick: loops the section or stops at its end. */
    fun service() {
        val end = loopEnd ?: return
        val pos = position ?: return
        if (pos >= end) {
            if (looping) player?.seekTo((loopStart * 1000).toLong(), MediaPlayer.SEEK_CLOSEST) else stop()
        }
    }

    fun stop() {
        runCatching { if (player?.isPlaying == true) player?.pause() }
    }

    fun release() {
        player?.release()
        player = null
        loadedPath = null
    }

    private fun prepare(path: String): MediaPlayer? {
        if (loadedPath == path && player != null) return player
        release()
        return try {
            MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                setDataSource(path)
                prepare()
            }.also { player = it; loadedPath = path }
        } catch (e: Exception) {
            null
        }
    }
}
