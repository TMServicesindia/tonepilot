package com.tonepilot.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
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
import com.tonepilot.app.strings

/** Everything needed to play one section, plus a practice loop at slower speeds. */
@Composable
fun SectionGuideScreen(app: AppState, songId: String, sectionId: String) {
    val g = remember(app.revision, songId, sectionId) { NativeBridge.cmd("sectionGuide", "songId" to songId, "sectionId" to sectionId) }
    if (g.has("error")) { Text(g.str("error"), Modifier.padding(16.dp)); return }
    var speed by remember { mutableFloatStateOf(0.75f) }
    val looping = app.practiceSectionId == sectionId
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row {
            Text(g.str("label"), fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            if (g.optBoolean("climax")) Text("CLIMAX", color = Palette.accent, fontWeight = FontWeight.Bold)
        }
        Caption("${g.optDouble("start").mmss()} – ${g.optDouble("end").mmss()}" +
            g.strings("changes").let { if (it.isEmpty()) "" else " · " + it.joinToString(" · ") })

        if (looping) LiveStrip(app)

        Card("Practice") {
            if (g.optBoolean("hasAudio")) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (s in listOf(0.5f, 0.75f, 0.9f, 1f)) {
                        FilterChip(selected = speed == s, onClick = { speed = s }, label = { Text("${(s * 100).toInt()}%") })
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { app.practice(songId, sectionId, g.optDouble("start"), g.optDouble("end"), speed) }) { Text("Loop this section") }
                    if (looping) OutlinedButton(onClick = { app.stopBacking() }) { Text("Stop") }
                }
                if (speed != 1f) Caption("Generated bass/drums pause below 100% speed; your tones always play.")
            } else {
                Caption("No audio file for this song — use the guide below with the metronome in Play.")
            }
            g.strings("practiceSteps").forEachIndexed { i, s -> Text("${i + 1}. $s", fontSize = 14.sp) }
        }

        Card("Tone") {
            Text(g.str("toneAdvice"), fontSize = 14.sp)
            Button(onClick = { app.command("activateSection", "songId" to songId, "sectionId" to sectionId) }) { Text("Use this tone on my keyboard") }
            val activity = g.objects("activity")
            if (activity.isNotEmpty()) {
                SectionLabel("Heard here")
                activity.forEach { a ->
                    Row {
                        Text(a.str("role"), fontSize = 14.sp, modifier = Modifier.width(130.dp))
                        Text("${(a.optDouble("level") * 100).toInt()}%", fontSize = 13.sp, modifier = Modifier.width(44.dp))
                        Caption(a.str("evidence"))
                    }
                }
            }
        }

        Card("Left hand · Root → Fifth → Root") {
            Text(g.str("leftHandPattern"))
            Caption(g.str("leftHandExample"))
            val chords = g.strings("chords")
            if (chords.isNotEmpty()) Text("Chords: " + chords.joinToString(" – "), fontFamily = FontFamily.Monospace, fontSize = 14.sp)
            if (g.str("rootMovement").isNotEmpty()) Caption("Bass movement heard: ${g.str("rootMovement")}")
        }

        Card("Right hand") {
            if (g.str("melodyRange").isNotEmpty()) Text("Melody range: ${g.str("melodyRange")}")
            val phrases = g.objects("phrases")
            if (phrases.isEmpty()) Caption("No clear melody in this section.")
            phrases.forEachIndexed { i, p ->
                Column {
                    Caption("Phrase ${i + 1} · ${p.optDouble("start").mmss()}${if (p.optBoolean("ornaments")) " · 〰" else ""}")
                    Text(p.strings("keys").joinToString(" "), fontFamily = FontFamily.Monospace, fontSize = 15.sp)
                }
            }
            val voicings = g.objects("voicings")
            if (voicings.isNotEmpty()) {
                SectionLabel("Chord shapes for fills (with inversions)")
                voicings.forEach { v ->
                    Row {
                        Text(v.str("chord"), fontWeight = FontWeight.SemiBold, modifier = Modifier.width(52.dp))
                        Text(v.strings("notes").joinToString(" "), fontFamily = FontFamily.Monospace, fontSize = 14.sp, modifier = Modifier.weight(1f))
                        Caption(v.str("inversion"))
                    }
                }
            }
        }

        val instructions = g.strings("instructions")
        if (instructions.isNotEmpty()) Card("How to play this section") { instructions.forEach { Text("• $it", fontSize = 14.sp) } }

        Row(Modifier.fillMaxWidth()) {
            if (g.str("previousId").isNotEmpty()) TextButton(onClick = {
                app.back(); app.open(Screen.SectionGuide(songId, g.str("previousId")))
            }) { Text("‹ ${g.str("previousLabel")}") }
            Spacer(Modifier.weight(1f))
            if (g.str("nextId").isNotEmpty()) TextButton(onClick = {
                app.back(); app.open(Screen.SectionGuide(songId, g.str("nextId")))
            }) { Text("${g.str("nextLabel")} ›") }
        }
        Box(Modifier.height(24.dp))
    }
}
