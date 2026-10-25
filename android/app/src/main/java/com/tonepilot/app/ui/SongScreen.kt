package com.tonepilot.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tonepilot.app.AppState
import com.tonepilot.app.NativeBridge
import com.tonepilot.app.Screen
import com.tonepilot.app.mmss
import com.tonepilot.app.objects
import com.tonepilot.app.str
import com.tonepilot.app.strings
import org.json.JSONObject

private val keyNames = listOf("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")

@Composable
fun SongScreen(app: AppState, songId: String) {
    val song = remember(app.revision, songId) { NativeBridge.cmd("song", "id" to songId) }
    if (song.has("error")) { Text(song.str("error"), Modifier.padding(16.dp)); return }
    val status = song.str("status")
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Text(song.str("title"), fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Caption(song.str("subtitle"))
        when (status) {
            "running" -> Card("Building your arrangement") {
                LinearProgressIndicator(progress = { song.optDouble("progress", 0.0).toFloat() }, modifier = Modifier.fillMaxWidth())
                Text(song.str("stage").ifEmpty { "Analysing on this phone…" })
                Caption("Tempo, key and chords → melody → sections and what plays in each → tones, layers and effects for every section.")
                TextButton(onClick = { app.command("cancelAnalysis", "id" to songId) }) { Text("Cancel") }
            }
            "failed", "notStarted" -> Card("Analysis") {
                Caption(song.str("error"), Palette.bad)
                if (song.optBoolean("hasAudio")) {
                    Button(onClick = { app.reanalyze(songId, song.str("audioFile")) }) { Text(if (status == "failed") "Try again" else "Analyse & arrange") }
                } else if (song.str("source") == "listened") {
                    Button(onClick = { app.open(Screen.Listen) }) { Text("Listen again to analyse") }
                }
            }
        }
        if (status == "completed") {
            ReadyCard(app, song)
            OverviewCard(song)
        }
        val sections = song.objects("sections")
        if (sections.isNotEmpty()) {
            Card("Song timeline") { Timeline(sections, song.optDouble("duration", 0.0)) { app.open(Screen.SectionGuide(songId, it)) } }
            Card("Sections & AI tones") {
                sections.forEach { SectionRow(app, songId, it) }
            }
        }
        if (status == "completed") CorrectionsCard(app, song)
        Box(Modifier.height(24.dp))
    }
}

@Composable
private fun ReadyCard(app: AppState, song: JSONObject) {
    val songId = song.str("id")
    Card("Ready to play") {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            song.optJSONObject("bpm")?.let { Chip(it.str("text"), it.optDouble("confidence") < 0.6 && !it.optBoolean("user")) }
            song.optJSONObject("key")?.let { Chip(it.str("text"), it.optDouble("confidence") < 0.6 && !it.optBoolean("user")) }
            song.optJSONObject("meter")?.let { Chip(it.str("text").substringBefore(" "), it.optDouble("confidence") < 0.6 && !it.optBoolean("user")) }
            Chip("${song.objects("sections").size} sections")
            if (song.str("melodySource").isNotEmpty()) Chip(song.str("melodySource"))
        }
        Caption(song.str("notice"), Palette.warn)
        Button(onClick = { app.playOnCasio(songId) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
            Text("Play on My Casio", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        }
        var showLimits by remember { mutableStateOf(false) }
        TextButton(onClick = { showLimits = !showLimits }) { Text(if (showLimits) "Hide what the AI can't do" else "What the AI can and can't do") }
        if (showLimits) song.strings("limitations").forEach { Caption("• $it") }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (song.optBoolean("hasAudio")) TextButton(onClick = { app.reanalyze(songId, song.str("audioFile")) }) { Text("Re-analyse") }
            if (song.str("source") == "listened") TextButton(onClick = { app.open(Screen.Listen) }) { Text("Listen again") }
        }
    }
}

@Composable
private fun OverviewCard(song: JSONObject) {
    Card("Song overview") {
        val rows = song.optJSONArray("overview")
        if (rows != null) for (i in 0 until rows.length()) {
            val r = rows.optJSONArray(i) ?: continue
            InfoRow(r.optString(0), r.optString(1))
        }
        val gaps = song.strings("gaps")
        if (gaps.isNotEmpty()) Caption("Not available for this audio: " + gaps.joinToString("; "), Palette.warn)
    }
}

@Composable
private fun Timeline(sections: List<JSONObject>, duration: Double, onTap: (String) -> Unit) {
    val total = maxOf(duration, sections.maxOf { it.optDouble("end", 0.0) }, 1.0)
    Row(Modifier.fillMaxWidth().height(34.dp).clip(RoundedCornerShape(6.dp))) {
        var cursor = 0.0
        for (s in sections) {
            val start = s.optDouble("start"); val end = s.optDouble("end")
            if (start > cursor) Box(Modifier.weight(((start - cursor) / total).toFloat().coerceAtLeast(0.001f)).fillMaxHeight().background(Palette.raised))
            Box(
                Modifier.weight(((end - start) / total).toFloat().coerceAtLeast(0.001f)).fillMaxHeight()
                    .padding(end = 1.dp)
                    .background(sectionColor(s.str("type")).copy(alpha = if (s.optBoolean("active")) 1f else 0.7f))
                    .clickable { onTap(s.str("id")) }
            )
            cursor = end
        }
        if (total > cursor) Box(Modifier.weight(((total - cursor) / total).toFloat().coerceAtLeast(0.001f)).fillMaxHeight().background(Palette.raised))
    }
    Caption("Tap a section for its guide.")
}

@Composable
private fun SectionRow(app: AppState, songId: String, s: JSONObject) {
    val active = s.optBoolean("active")
    var menu by remember { mutableStateOf(false) }
    Column(
        Modifier.fillMaxWidth()
            .background(if (active) Palette.raised else Palette.panel, RoundedCornerShape(10.dp))
            .clickable { app.open(Screen.SectionGuide(songId, s.str("id"))) }
            .padding(10.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(6.dp).height(38.dp).background(sectionColor(s.str("type")), RoundedCornerShape(3.dp)))
            Column(Modifier.weight(1f).padding(start = 10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(s.str("label"), fontWeight = FontWeight.SemiBold)
                    if (s.optBoolean("climax")) Text("  CLIMAX", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Palette.accent)
                    if (!s.optBoolean("user") && s.optDouble("confidence", 1.0) < 0.5) Text("  ?", color = Palette.warn)
                }
                Caption("${s.optDouble("start").mmss()} – ${s.optDouble("end").mmss()}")
            }
            TextButton(onClick = { app.command("activateSection", "songId" to songId, "sectionId" to s.str("id")) }) {
                Text(if (active) "Playing" else "Use tone", color = if (active) Palette.accent else Palette.muted)
            }
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, "More") }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Section guide & practice") }, onClick = { menu = false; app.open(Screen.SectionGuide(songId, s.str("id"))) })
                    DropdownMenuItem(text = { Text("Regenerate this section's tone") }, onClick = {
                        menu = false; app.command("regenerateSection", "songId" to songId, "sectionId" to s.str("id"))
                    })
                    if (s.optBoolean("canRestore")) DropdownMenuItem(text = { Text("Restore AI Original") }, onClick = {
                        menu = false; app.command("restoreAIOriginal", "songId" to songId, "sectionId" to s.str("id"))
                    })
                }
            }
        }
        if (s.str("toneName").isNotEmpty()) {
            Text(s.str("toneName"), fontSize = 14.sp, modifier = Modifier.padding(start = 16.dp, top = 4.dp))
            Caption(s.str("layers").let { if (it.isEmpty()) "" else "    $it" })
        }
    }
}

@Composable
private fun CorrectionsCard(app: AppState, song: JSONObject) {
    val songId = song.str("id")
    Card("Correct the analysis") {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Tempo", color = Palette.muted, modifier = Modifier.width(64.dp))
            val bpm = song.optDouble("bpmValue", 0.0)
            if (bpm > 0) {
                Text("%.1f".format(bpm), modifier = Modifier.weight(1f))
                OutlinedButton(onClick = { app.command("setBPM", "songId" to songId, "value" to bpm / 2) }) { Text("÷2") }
                OutlinedButton(onClick = { app.command("setBPM", "songId" to songId, "value" to bpm * 2) }) { Text("×2") }
            } else Text("Not detected", color = Palette.muted)
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Key", color = Palette.muted, modifier = Modifier.width(64.dp))
            var open by remember { mutableStateOf(false) }
            Box {
                OutlinedButton(onClick = { open = true }) { Text(song.optJSONObject("key")?.str("text") ?: "Set key") }
                DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                    for (t in 0 until 12) for (mode in listOf("major", "minor")) {
                        DropdownMenuItem(text = { Text("${keyNames[t]} $mode") }, onClick = {
                            open = false; app.command("setKey", "songId" to songId, "tonic" to t, "mode" to mode)
                        })
                    }
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Meter", color = Palette.muted, modifier = Modifier.width(64.dp))
            val meter = song.optInt("meterValue", 4)
            FilterChip(selected = meter == 3, onClick = { app.command("setMeter", "songId" to songId, "value" to 3) }, label = { Text("3/4 · 6/8") })
            FilterChip(selected = meter == 4, onClick = { app.command("setMeter", "songId" to songId, "value" to 4) }, label = { Text("4/4") })
        }
    }
}
