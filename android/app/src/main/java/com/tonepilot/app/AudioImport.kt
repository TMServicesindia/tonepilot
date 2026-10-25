package com.tonepilot.app

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.nio.ByteOrder
import java.util.UUID

/** Copies a picked audio file into TonePilot's folder and decodes it to mono samples for analysis. */
object AudioImport {
    class ImportFailure(message: String) : Exception(message)

    fun displayName(context: Context, uri: Uri): String {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0)?.let { return it }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "Song"
    }

    /** Returns the stored file name inside [audioDir]. The original file is never modified. */
    fun copy(context: Context, uri: Uri, audioDir: File, originalName: String): String {
        val ext = originalName.substringAfterLast('.', "mp3").lowercase().take(5).ifBlank { "mp3" }
        val name = "${UUID.randomUUID()}.$ext"
        audioDir.mkdirs()
        val dest = File(audioDir, name)
        val input = context.contentResolver.openInputStream(uri) ?: throw ImportFailure("Couldn't open “$originalName”.")
        input.use { i -> dest.outputStream().use { o -> i.copyTo(o, 1 shl 16) } }
        return name
    }

    fun durationSeconds(file: File): Double? = try {
        MediaMetadataRetriever().run {
            setDataSource(file.path)
            val ms = extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            release()
            ms?.let { it / 1000.0 }
        }
    } catch (e: Exception) {
        null
    }

    /**
     * Decodes [file] with the phone's codecs and streams mono float samples to the Swift core
     * under [key]. Returns the number of samples delivered.
     */
    fun decodeToCore(file: File, key: String, cancelled: () -> Boolean = { false }): Long {
        val extractor = MediaExtractor()
        extractor.setDataSource(file.path)
        val track = (0 until extractor.trackCount).firstOrNull {
            extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
        } ?: run { extractor.release(); throw ImportFailure("No audio track found.") }
        extractor.selectTrack(track)
        val inFormat = extractor.getTrackFormat(track)
        val codec = MediaCodec.createDecoderByType(inFormat.getString(MediaFormat.KEY_MIME)!!)
        codec.configure(inFormat, null, null, 0)
        codec.start()

        var channels = inFormat.getIntegerOrDefault(MediaFormat.KEY_CHANNEL_COUNT, 2)
        var rate = inFormat.getIntegerOrDefault(MediaFormat.KEY_SAMPLE_RATE, 44100)
        var encoding = AudioFormat.ENCODING_PCM_16BIT
        var begun = false
        val chunk = FloatArray(1 shl 16)
        var filled = 0
        var delivered = 0L
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false

        fun flush() {
            if (filled > 0) { NativeBridge.pcmAppend(key, chunk, filled); delivered += filled; filled = 0 }
        }
        fun begin() {
            if (!begun) { NativeBridge.cmd("pcmBegin", "key" to key, "sampleRate" to rate.toDouble()); begun = true }
        }

        try {
            while (!outputDone) {
                if (cancelled()) throw ImportFailure("Analysis was cancelled.")
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(10_000)
                    if (i >= 0) {
                        val buf = codec.getInputBuffer(i)!!
                        val n = extractor.readSampleData(buf, 0)
                        if (n < 0) {
                            codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(i, 0, n, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val f = codec.outputFormat
                        channels = f.getIntegerOrDefault(MediaFormat.KEY_CHANNEL_COUNT, channels)
                        rate = f.getIntegerOrDefault(MediaFormat.KEY_SAMPLE_RATE, rate)
                        encoding = f.getIntegerOrDefault(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                    }
                    o >= 0 -> {
                        begin()
                        val buf = codec.getOutputBuffer(o)!!.order(ByteOrder.nativeOrder())
                        buf.position(info.offset)
                        buf.limit(info.offset + info.size)
                        val ch = channels.coerceAtLeast(1)
                        if (encoding == AudioFormat.ENCODING_PCM_FLOAT) {
                            val fb = buf.asFloatBuffer()
                            val frames = fb.remaining() / ch
                            for (f in 0 until frames) {
                                var sum = 0f
                                for (c in 0 until ch) sum += fb.get()
                                chunk[filled++] = sum / ch
                                if (filled == chunk.size) flush()
                            }
                        } else {
                            val sb = buf.asShortBuffer()
                            val frames = sb.remaining() / ch
                            for (f in 0 until frames) {
                                var sum = 0f
                                for (c in 0 until ch) sum += sb.get() / 32768f
                                chunk[filled++] = sum / ch
                                if (filled == chunk.size) flush()
                            }
                        }
                        codec.releaseOutputBuffer(o, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                }
            }
            begin()
            flush()
        } finally {
            runCatching { codec.stop() }
            codec.release()
            extractor.release()
        }
        return delivered
    }

    private fun MediaFormat.getIntegerOrDefault(key: String, default: Int): Int =
        if (containsKey(key)) getInteger(key) else default
}
