package com.tonepilot.app

import android.app.Application
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File

/** Where the UI is. Tabs at the bottom; pages pushed on top of them. */
sealed class Screen {
    data object Library : Screen()
    data object Play : Screen()
    data object Settings : Screen()
    data class Song(val id: String) : Screen()
    data class SectionGuide(val songId: String, val sectionId: String) : Screen()
    data object Tones : Screen()
    data object Listen : Screen()
}

/**
 * App-wide state for the Compose UI. Owns MIDI input and the backing player, polls the Swift
 * core for state, and runs imports/analysis off the main thread.
 */
class AppState(private val app: Application) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    val midi = MidiInput(app)
    val player = BackingPlayer()

    var startError by mutableStateOf<String?>(null)
    var started by mutableStateOf(false)
    var preparing by mutableStateOf("Starting…")
    var state by mutableStateOf(JSONObject())
    var songs by mutableStateOf(listOf<JSONObject>())
    var live by mutableStateOf(JSONObject())
    /** Bumped after any change so open pages re-read their data. */
    var revision by mutableIntStateOf(0)
    var importError by mutableStateOf<String?>(null)
    var toast by mutableStateOf<String?>(null)
    var practiceSectionId by mutableStateOf<String?>(null)

    val stack = mutableStateListOf<Screen>(Screen.Library)
    val current: Screen get() = stack.last()

    lateinit var root: File
        private set
    val audioDir: File get() = File(root, "Audio")

    fun open(screen: Screen) { stack.add(screen) }
    fun tab(screen: Screen) { stack.clear(); stack.add(screen) }
    fun back(): Boolean = if (stack.size > 1) { stack.removeAt(stack.size - 1); true } else false

    fun start() {
        if (started) return
        root = File(app.filesDir, "TonePilot")
        scope.launch {
            val error = withContext(Dispatchers.IO) {
                preparing = "Preparing instrument sounds…"
                try {
                    installSoundFont()
                    NativeBridge.start(root.path)
                } catch (e: Throwable) {
                    "TonePilot's sound engine couldn't start: ${e.message}"
                }
            }
            started = true
            if (error.isNotEmpty()) startError = error
            midi.start()
            refresh()
            poll()
        }
    }

    /** Copies the bundled GeneralUser GS SoundFont out of the APK once (≈30 MB). */
    private fun installSoundFont() {
        val dir = File(root, "SoundFonts").apply { mkdirs() }
        val assets = app.assets.list("")?.toList() ?: emptyList()
        for (name in assets.filter { it.endsWith(".sf2", ignoreCase = true) }) {
            val dest = File(dir, name)
            val size = runCatching { app.assets.openFd(name).use { it.length } }.getOrDefault(-1L)
            if (dest.exists() && (size < 0 || dest.length() == size)) continue
            val tmp = File(dir, "$name.part")
            app.assets.open(name).use { i -> tmp.outputStream().use { o -> i.copyTo(o, 1 shl 16) } }
            tmp.renameTo(dest)
        }
    }

    private fun poll() {
        scope.launch {
            var n = 0
            while (true) {
                tick()
                if (n % 5 == 0) refreshState()
                if (n % 10 == 0 && (state.optJSONObject("analyses")?.length() ?: 0) > 0) { refreshLibrary(); revision++ }
                if (n % 100 == 0) NativeBridge.cmd("maintenance")
                n++
                delay(50)
            }
        }
    }

    private fun tick() {
        player.service()
        val pos = player.position
        NativeBridge.cmd("tick", "time" to (pos ?: -1.0), "rate" to player.rate.toDouble())
        if (current == Screen.Play || current is Screen.SectionGuide) live = NativeBridge.cmd("liveGuide")
        if (!player.isPlaying && practiceSectionId != null) practiceSectionId = null
    }

    fun refreshState() { state = NativeBridge.cmd("state") }
    fun refreshLibrary() { songs = NativeBridge.cmd("library").objects("songs") }
    fun refresh() { refreshState(); refreshLibrary(); revision++ }

    fun command(name: String, vararg args: Pair<String, Any?>): JSONObject {
        val r = NativeBridge.cmd(name, *args)
        r.optString("error").takeIf { it.isNotEmpty() }?.let { toast = it }
        refresh()
        return r
    }

    // MARK: Import & analysis

    fun importAudio(context: Context, uri: Uri) {
        importError = null
        scope.launch {
            while (!started) delay(100)
            val result = withContext(Dispatchers.IO) { runImport(context, uri) }
            refresh()
            when (result) {
                is ImportResult.Failed -> importError = result.message
                is ImportResult.Started -> open(Screen.Song(result.songId))
            }
        }
    }

    private sealed class ImportResult {
        data class Started(val songId: String) : ImportResult()
        data class Failed(val message: String) : ImportResult()
    }

    private fun runImport(context: Context, uri: Uri): ImportResult {
        val original = AudioImport.displayName(context, uri)
        val fileName = try {
            AudioImport.copy(context, uri, audioDir, original)
        } catch (e: Exception) {
            return ImportResult.Failed("Couldn't copy “$original”: ${e.message}")
        }
        val file = File(audioDir, fileName)
        val duration = AudioImport.durationSeconds(file)
        if (duration == null || duration <= 0) {
            file.delete()
            return ImportResult.Failed("“$original” couldn't be read as audio. Check that it plays, then try again.")
        }
        val id = NativeBridge.cmd("importSong", "fileName" to fileName, "originalName" to original, "duration" to duration).str("id")
        if (id.isEmpty()) return ImportResult.Failed("Couldn't add “$original” to the library.")
        scope.launch { refresh() }
        Thread { decodeAndAnalyze(id, file) }.apply { name = "TonePilot-analysis"; start() }
        return ImportResult.Started(id)
    }

    /** Re-analyse a song already in the library (Try again / Re-analyse). */
    fun reanalyze(songId: String, audioFile: String) {
        val file = File(audioDir, audioFile)
        NativeBridge.cmd("analysisStarted", "id" to songId, "stage" to "Decoding audio…")
        refresh()
        Thread { decodeAndAnalyze(songId, file) }.apply { name = "TonePilot-analysis"; start() }
    }

    private fun decodeAndAnalyze(songId: String, file: File) {
        try {
            val n = AudioImport.decodeToCore(file, songId)
            if (n == 0L) throw AudioImport.ImportFailure("The audio couldn't be read. Check that it plays, then try again.")
            NativeBridge.cmd("analyze", "id" to songId, "key" to songId)
        } catch (e: Exception) {
            NativeBridge.cmd("analysisFailed", "id" to songId,
                "message" to (e.message ?: "The audio couldn't be read. Check that it plays, then try again."))
        }
        scope.launch { refresh() }
    }

    // MARK: Listen Mode

    fun finishListening(title: String, link: String?, onDone: (String?) -> Unit) {
        ListenService.stop(app)
        scope.launch {
            val r = withContext(Dispatchers.IO) { NativeBridge.cmd("listenFinish", "title" to title, "link" to link) }
            refresh()
            val id = r.str("id").ifEmpty { null }
            if (id == null) toast = r.str("error").ifEmpty { "Nothing was recorded." }
            onDone(id)
        }
    }

    // MARK: Playing

    fun songAudioPath(song: JSONObject): String? =
        song.str("audioFile").takeIf { song.optBoolean("hasAudio") && it.isNotEmpty() }?.let { File(audioDir, it).path }

    /** Plays the song from [from] as backing/clock; silent when the backing track is switched off. */
    fun playBacking(songId: String, from: Double, to: Double? = null, loop: Boolean = false, speed: Float = 1f, forceAudible: Boolean = false) {
        val song = NativeBridge.cmd("song", "id" to songId)
        val path = songAudioPath(song) ?: run { toast = "This song has no audio file."; return }
        NativeBridge.cmd("ensurePerformance", "id" to songId)
        val acc = NativeBridge.cmd("state").optJSONObject("accompaniment")
        val volume = if (forceAudible || acc?.optBoolean("backingTrack") == true) (acc?.optDouble("backingTrackLevel", 0.8) ?: 0.8).toFloat() else 0f
        player.play(path, from, to, loop, speed, volume)
    }

    fun practice(songId: String, sectionId: String, start: Double, end: Double, speed: Float) {
        if (state.str("songId") != songId) NativeBridge.cmd("startPerformance", "id" to songId)
        playBacking(songId, start, end, loop = true, speed = speed, forceAudible = true)
        NativeBridge.cmd("activateSection", "songId" to songId, "sectionId" to sectionId)
        practiceSectionId = sectionId
        refresh()
    }

    fun stopBacking() {
        player.stop()
        practiceSectionId = null
    }

    fun playOnCasio(songId: String) {
        command("startPerformance", "id" to songId)
        tab(Screen.Play)
    }

    /** True when sound would come out of the phone's own speaker instead of the cable to the Casio. */
    fun isPhoneSpeaker(): Boolean {
        val am = app.getSystemService(AudioManager::class.java) ?: return false
        val outs = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val external = setOf(AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_LINE_ANALOG, AudioDeviceInfo.TYPE_LINE_DIGITAL,
            AudioDeviceInfo.TYPE_AUX_LINE, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)
        return outs.none { it.type in external }
    }

    fun outputDescription(): String {
        val am = app.getSystemService(AudioManager::class.java) ?: return ""
        val names = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .filter { it.type != AudioDeviceInfo.TYPE_BUILTIN_EARPIECE && it.type != AudioDeviceInfo.TYPE_TELEPHONY }
            .map { "${it.productName} (${typeName(it.type)})" }
        return names.joinToString(", ")
    }

    private fun typeName(t: Int) = when (t) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "phone speaker"
        AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "3.5 mm jack"
        AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET -> "USB audio"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth — adds delay"
        AudioDeviceInfo.TYPE_LINE_ANALOG, AudioDeviceInfo.TYPE_AUX_LINE -> "line out"
        else -> "type $t"
    }

    fun flush() { if (started) NativeBridge.cmd("flush") }
}
