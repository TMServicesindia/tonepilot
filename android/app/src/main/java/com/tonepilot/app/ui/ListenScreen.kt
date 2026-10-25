package com.tonepilot.app.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.tonepilot.app.AppState
import com.tonepilot.app.ListenService
import com.tonepilot.app.NativeBridge
import com.tonepilot.app.Screen
import com.tonepilot.app.mmss
import kotlinx.coroutines.delay
import org.json.JSONObject

/**
 * Listen Mode: play the song in YouTube / YouTube Music / Spotify / JioSaavn; TonePilot listens
 * through the microphone, keeps the audio in memory only, and builds the arrangement when it ends.
 */
@Composable
fun ListenScreen(app: AppState) {
    val context = LocalContext.current
    var title by remember { mutableStateOf("") }
    var link by remember { mutableStateOf("") }
    var listening by remember { mutableStateOf(false) }
    var analysing by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf(JSONObject()) }
    var error by remember { mutableStateOf<String?>(null) }

    fun begin() {
        NativeBridge.cmd("listenBegin")
        ListenService.start(context)
        listening = true
        val url = link.trim()
        if (url.startsWith("http")) {
            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
    }
    fun finish() {
        listening = false
        analysing = true
        app.finishListening(title.ifBlank { link.trim().ifBlank { "Listened song" } }, link.trim().ifEmpty { null }) { id ->
            analysing = false
            if (id != null) { app.back(); app.open(Screen.Song(id)) }
        }
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
        if (granted[Manifest.permission.RECORD_AUDIO] == true) begin()
        else error = "TonePilot needs the microphone to listen. Allow it in Settings › Apps › TonePilot › Permissions."
    }
    fun start() {
        error = null
        val needed = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= 33) needed += Manifest.permission.POST_NOTIFICATIONS
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) begin()
        else permission.launch(needed.toTypedArray())
    }

    LaunchedEffect(listening) {
        while (listening) {
            status = NativeBridge.cmd("listenStatus")
            ListenService.Recorder.error?.let { error = it; listening = false; ListenService.stop(context) }
            if (status.optBoolean("shouldStop")) finish()
            delay(250)
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        when {
            analysing -> Card {
                CircularProgressIndicator()
                Text("Analysing what TonePilot heard…")
                Caption("Tempo, key, chords, melody and sections → tones for every section.")
            }
            listening -> Card("Listening") {
                Text(status.optDouble("elapsed", 0.0).mmss(), fontSize = 40.sp, fontWeight = FontWeight.Bold)
                val level = status.optDouble("level", 0.0).toFloat()
                Box(Modifier.fillMaxWidth().height(8.dp).background(Palette.raised, RoundedCornerShape(4.dp))) {
                    Box(Modifier.fillMaxWidth((level * 6).coerceIn(0f, 1f)).height(8.dp).background(Palette.good, RoundedCornerShape(4.dp)))
                }
                if (status.optBoolean("tooQuiet")) Caption("Very quiet — turn the music up or move the phone closer.", Palette.warn)
                Caption("TonePilot stops by itself when the song ends.")
                Button(onClick = { finish() }, modifier = Modifier.fillMaxWidth()) { Text("Stop & build") }
                OutlinedButton(onClick = { listening = false; ListenService.stop(context); NativeBridge.cmd("listenCancel") }, modifier = Modifier.fillMaxWidth()) { Text("Cancel") }
            }
            else -> {
                Card("How it works") {
                    Text("1. Turn the music volume up (70–90%) in a quiet room.")
                    Text("2. Paste the song's link (YouTube, YouTube Music, Spotify, JioSaavn…) and tap Open & listen — or tap Start listening and play it yourself.")
                    Text("3. Play the song from the beginning. A nearby speaker or second device gives the cleanest result.")
                    Caption("The audio stays in memory on this phone and is discarded after analysis. Nothing is downloaded or saved.")
                }
                OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text("Song name (optional)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = link, onValueChange = { link = it }, label = { Text("Song link (optional)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Button(onClick = { start() }, modifier = Modifier.fillMaxWidth()) { Text(if (link.trim().startsWith("http")) "Open & listen" else "Start listening") }
            }
        }
        error?.let { Caption(it, Palette.bad) }
    }
}
