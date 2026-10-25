package com.tonepilot.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

object Palette {
    val background = Color(0xFF0F1115)
    val panel = Color(0xFF1A1E26)
    val raised = Color(0xFF262C37)
    val accent = Color(0xFFFFB347)
    val good = Color(0xFF6FD08C)
    val warn = Color(0xFFFFC857)
    val bad = Color(0xFFFF6B6B)
    val muted = Color(0xFF9AA3B2)
}

val TonePilotColors = darkColorScheme(
    primary = Palette.accent,
    onPrimary = Color(0xFF1A1200),
    secondary = Color(0xFF8AB4F8),
    background = Palette.background,
    surface = Palette.panel,
    surfaceVariant = Palette.raised,
    surfaceContainer = Palette.panel,
    onBackground = Color(0xFFE8EAED),
    onSurface = Color(0xFFE8EAED),
)

/** A titled panel, like the cards on the iPhone version. */
@Composable
fun Card(title: String? = null, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .background(Palette.panel, RoundedCornerShape(14.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (title != null) Text(title.uppercase(), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Palette.muted)
        content()
    }
}

@Composable
fun InfoRow(label: String, value: String) {
    if (value.isEmpty()) return
    Row(Modifier.fillMaxWidth()) {
        Text(label, color = Palette.muted, modifier = Modifier.width(96.dp), style = MaterialTheme.typography.bodyMedium)
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
fun Chip(text: String, uncertain: Boolean = false) {
    Text(
        text + if (uncertain) " ?" else "",
        fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
        color = if (uncertain) Palette.warn else Color.Unspecified,
        modifier = Modifier.background(Palette.raised, RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 5.dp)
    )
}

@Composable
fun Caption(text: String, color: Color = Palette.muted) {
    if (text.isNotEmpty()) Text(text, fontSize = 13.sp, color = color)
}

@Composable
fun SectionLabel(text: String) {
    Text(text.uppercase(), fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Palette.muted)
}

/** Colour for a section type in timelines and rows. */
fun sectionColor(type: String): Color = when (type) {
    "intro" -> Color(0xFF7E8CE0)
    "verse" -> Color(0xFF4FB3BF)
    "preChorus" -> Color(0xFF9CCC65)
    "chorus" -> Color(0xFFFFB347)
    "bridge" -> Color(0xFFBA68C8)
    "interlude", "instrumentalBreak" -> Color(0xFF64B5F6)
    "outro" -> Color(0xFF90A4AE)
    else -> Color(0xFFA1887F)
}
