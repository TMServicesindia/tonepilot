package com.tonepilot.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tonepilot.app.AppState
import com.tonepilot.app.NativeBridge
import com.tonepilot.app.Screen
import com.tonepilot.app.mmss
import com.tonepilot.app.objects
import com.tonepilot.app.str

/** The performance page: the tone you hear from the Casio keys, the live guide and the song clock. */
@Composable
fun PlayScreen(app: AppState) {
    val st = app.state
    val songId = st.str("songId")
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        ConnectionCard(app)

        Card("Now playing on your keyboard") {
            Text(st.str("toneName"), fontSize = 24.sp, fontWeight = FontWeight.Bold)
            Caption(st.objects("layers").joinToString(" + ") { it.str("name") })
            if (!st.optBoolean("soundFontReady")) Caption("Loading instrument sounds…", Palette.warn)
            st.optJSONArray("patchErrors")?.let { a -> if (a.length() > 0) Caption(a.optString(0), Palette.bad) }
            Button(onClick = { app.open(Screen.Tones) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Text("Choose tone", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }
            LayerMixer(app)
        }

        if (songId.isNotEmpty()) SongPerformance(app)
        else Caption("Open a song in the Library and tap Play on My Casio for section tones, the chord guide and backing.")

        Card("Test without the keyboard") { AuditionStrip() }
        Box(Modifier.height(24.dp))
    }
}

@Composable
private fun ConnectionCard(app: AppState) {
    val devices = app.midi.deviceNames
    val speaker = remember(app.state) { app.isPhoneSpeaker() }
    Card {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(10.dp).height(10.dp).background(if (devices.isEmpty()) Palette.bad else Palette.good, RoundedCornerShape(5.dp)))
            Text(if (devices.isEmpty()) "  No keyboard connected" else "  " + devices.joinToString(), fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            TextButton(onClick = { NativeBridge.cmd("panic") }) { Text("All notes off") }
        }
        if (devices.isEmpty()) Caption("Connect the Casio's USB TO HOST port to the phone (USB-C to USB-B cable or OTG adapter). It appears here automatically.")
        if (speaker) Caption("Sound is coming from the phone speaker. Connect a cable from the phone's 3.5 mm jack (or USB audio adapter) to the Casio's AUDIO IN.", Palette.warn)
        val peak = app.state.optDouble("peak", 0.0).toFloat()
        Box(Modifier.fillMaxWidth().height(4.dp).background(Palette.raised, RoundedCornerShape(2.dp))) {
            Box(Modifier.fillMaxWidth(peak.coerceIn(0f, 1f)).height(4.dp)
                .background(if (app.state.optBoolean("clipped")) Palette.bad else Palette.good, RoundedCornerShape(2.dp)))
        }
    }
}

@Composable
private fun LayerMixer(app: AppState) {
    val layers = app.state.objects("layers")
    var expanded by remember { mutableStateOf(false) }
    TextButton(onClick = { expanded = !expanded }) { Text(if (expanded) "Hide layers" else "Layers (volume · octave · mute)") }
    if (!expanded) return
    layers.forEach { l ->
        val index = l.optInt("index")
        Column(Modifier.fillMaxWidth().background(Palette.raised, RoundedCornerShape(8.dp)).padding(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(l.str("name"), fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                Caption(l.str("role"))
                Switch(checked = !l.optBoolean("muted"), onCheckedChange = { on -> app.command("editLayer", "index" to index, "muted" to !on) })
            }
            var volume by remember(l.toString()) { mutableStateOf(l.optDouble("volume", 0.8).toFloat()) }
            Slider(value = volume, onValueChange = { volume = it }, onValueChangeFinished = { app.command("editLayer", "index" to index, "volume" to volume.toDouble()) })
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Caption("Octave")
                OutlinedButton(onClick = { app.command("editLayer", "index" to index, "octave" to l.optInt("octave") - 1) }) { Text("−") }
                Text(l.optInt("octave").let { if (it > 0) "+$it" else "$it" })
                OutlinedButton(onClick = { app.command("editLayer", "index" to index, "octave" to l.optInt("octave") + 1) }) { Text("+") }
            }
        }
    }
    Caption("Changes are saved as your own copy; the AI Original stays unchanged.")
}

@Composable
private fun SongPerformance(app: AppState) {
    val st = app.state
    val songId = st.str("songId")
    val playing = app.player.isPlaying
    Card(st.str("songTitle")) {
        Text("Section: " + st.str("sectionLabel").ifEmpty { "—" }, fontWeight = FontWeight.SemiBold)
        if (st.str("pendingSuggestion").isNotEmpty()) {
            Button(onClick = { app.command("confirmSuggestion") }, modifier = Modifier.fillMaxWidth()) {
                Text("Switch to ${st.str("pendingLabel")} ›")
            }
        }
        LiveStrip(app)
        val reference = st.str("reference")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (reference == "timer") {
                if (st.optBoolean("transportPlaying")) OutlinedButton(onClick = { app.command("stopClock") }) { Text("Stop clock") }
                else Button(onClick = { app.command("startClock") }) { Text("Start clock on beat 1") }
            } else if (st.optBoolean("hasAudio")) {
                if (playing) Button(onClick = { app.stopBacking() }) { Text("Stop") }
                else {
                    Button(onClick = { app.playBacking(songId, 0.0) }) { Text("Play from start") }
                    val pos = st.optDouble("position", -1.0)
                    if (pos > 0) OutlinedButton(onClick = { app.playBacking(songId, pos) }) { Text("From ${pos.mmss()}") }
                }
            }
        }
        if (reference == "backingTrack" && !st.optBoolean("hasAudio")) Caption("No audio file: switch the timing to Clock and tap Start on the song's first beat.")

        SectionLabel("Tone switching")
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for ((mode, label) in listOf("automatic" to "Automatic", "assisted" to "Assisted", "manual" to "Manual")) {
                FilterChip(selected = st.str("switchMode") == mode, onClick = { app.command("setSwitching", "songId" to songId, "mode" to mode) }, label = { Text(label) })
            }
        }
        SectionLabel("Timing from")
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for ((ref, label) in listOf("backingTrack" to "Song audio", "timer" to "Clock", "none" to "None")) {
                FilterChip(selected = reference == ref, onClick = { app.command("setSwitching", "songId" to songId, "reference" to ref) }, label = { Text(label) })
            }
        }
        Accompaniment(app)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val t = st.optInt("transpose")
            Caption("Transpose guide")
            OutlinedButton(onClick = { app.command("setTranspose", "songId" to songId, "value" to t - 1) }) { Text("−") }
            Text(if (t > 0) "+$t" else "$t")
            OutlinedButton(onClick = { app.command("setTranspose", "songId" to songId, "value" to t + 1) }) { Text("+") }
        }
        TextButton(onClick = { app.open(Screen.Song(songId)) }) { Text("Open song page") }
    }
}

@Composable
private fun Accompaniment(app: AppState) {
    val st = app.state
    val songId = st.str("songId")
    val acc = st.optJSONObject("accompaniment") ?: return
    SectionLabel("Backing & accompaniment (off by default)")
    for ((key, label) in listOf("backingTrack" to "Song audio (backing track)", "bass" to "Bass (root → fifth)",
        "drums" to "Drums", "metronome" to "Metronome", "melodyGuide" to "Melody guide (app plays the tune)")) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(label, modifier = Modifier.weight(1f), fontSize = 14.sp)
            Switch(checked = acc.optBoolean(key), onCheckedChange = { on ->
                app.command("setAccompaniment", "songId" to songId, key to on)
                if (key == "backingTrack") app.player.setVolume(if (on) acc.optDouble("backingTrackLevel", 0.8).toFloat() else 0f)
            })
        }
    }
}

/** Current chord as Root → Fifth → Root, next chord, and the next melody keys. */
@Composable
fun LiveStrip(app: AppState) {
    val live = app.live
    if (!live.optBoolean("available")) return
    Column(Modifier.fillMaxWidth().background(Palette.raised, RoundedCornerShape(12.dp)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                SectionLabel("Left hand")
                if (live.has("pattern")) {
                    Text(live.str("pattern"), fontSize = 28.sp, fontWeight = FontWeight.Bold)
                    Caption("${live.str("chord")} · ${live.str("notes")}")
                } else {
                    Text(if (live.optBoolean("clock")) "—" else "Start the song or clock", color = Palette.muted, fontSize = 18.sp)
                }
            }
            if (live.has("nextChord")) Column(horizontalAlignment = Alignment.End) {
                SectionLabel("Next")
                Text(live.str("nextChord"), fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                Caption("in %.1f s".format(live.optDouble("nextIn")))
            }
        }
        if (live.optBoolean("drone")) Caption("No clear chord here — play the Sa–Pa drone or follow the melody.", Palette.warn)
        Row {
            SectionLabel("Right hand")
            if (live.optBoolean("tricky")) Text("  Tricky phrase", fontSize = 11.sp, color = Palette.warn)
        }
        val melody = live.objects("melody")
        if (melody.isEmpty()) Caption(if (live.optBoolean("hasMelody")) "—" else "No melody estimate for this song")
        else Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            melody.forEachIndexed { i, n ->
                Text(n.str("key") + if (n.optBoolean("ornament")) "〰" else "",
                    fontFamily = FontFamily.Monospace, fontSize = if (i == 0) 18.sp else 14.sp, fontWeight = if (i == 0) FontWeight.Bold else FontWeight.Normal,
                    modifier = Modifier.background(if (i == 0 && n.optBoolean("now")) Palette.accent.copy(alpha = 0.35f) else Palette.panel, RoundedCornerShape(6.dp))
                        .padding(horizontal = 8.dp, vertical = 4.dp))
            }
        }
    }
}

/** An on-screen octave (C4–C5) that plays the selected tone through the same path as the Casio. */
@Composable
fun AuditionStrip() {
    val whites = listOf(60, 62, 64, 65, 67, 69, 71, 72)
    val names = listOf("C", "D", "E", "F", "G", "A", "B", "C")
    Row(Modifier.fillMaxWidth().height(110.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        whites.forEachIndexed { i, note ->
            var down by remember { mutableStateOf(false) }
            Box(
                Modifier.weight(1f).fillMaxSize()
                    .background(if (down) Palette.accent else Color(0xFFF2F2F2), RoundedCornerShape(bottomStart = 6.dp, bottomEnd = 6.dp))
                    .pointerInput(note) {
                        detectTapGestures(onPress = {
                            down = true
                            NativeBridge.cmd("audition", "note" to note, "on" to true)
                            tryAwaitRelease()
                            NativeBridge.cmd("audition", "note" to note, "on" to false)
                            down = false
                        })
                    },
                contentAlignment = Alignment.BottomCenter
            ) { Text(names[i], color = Color.Black, fontSize = 12.sp, modifier = Modifier.padding(bottom = 6.dp)) }
        }
    }
    Caption("Press keys here or on your Casio to hear the selected tone.")
}
