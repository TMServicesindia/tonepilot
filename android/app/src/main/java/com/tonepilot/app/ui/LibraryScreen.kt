package com.tonepilot.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExtendedFloatingActionButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tonepilot.app.AppState
import com.tonepilot.app.Screen
import com.tonepilot.app.str
import org.json.JSONObject

@Composable
fun LibraryScreen(app: AppState) {
    val context = LocalContext.current
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) app.importAudio(context, uri)
    }
    fun pick() = picker.launch(arrayOf("audio/*"))
    var menu by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf<JSONObject?>(null) }

    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            Modifier.fillMaxSize().padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            app.importError?.let { e ->
                item {
                    Card {
                        Text(e, color = Palette.bad)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = { pick() }) { Text("Try again") }
                            TextButton(onClick = { app.importError = null }) { Text("Dismiss") }
                        }
                    }
                }
            }
            if (app.songs.isEmpty()) {
                item { EmptyLibrary(onImport = { pick() }, onListen = { app.open(Screen.Listen) }) }
            }
            items(app.songs, key = { it.str("id") }) { song ->
                SongRow(song, onOpen = { app.open(Screen.Song(song.str("id"))) }, onDelete = { confirmDelete = song })
            }
            item { Spacer(Modifier.height(88.dp)) }
        }
        Box(Modifier.align(Alignment.BottomEnd).padding(16.dp)) {
            ExtendedFloatingActionButton(onClick = { menu = true }, icon = { Icon(Icons.Filled.Add, null) }, text = { Text("Add song") })
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("Import MP3 / audio file") }, onClick = { menu = false; pick() })
                DropdownMenuItem(text = { Text("Listen to a song (streaming app)") }, onClick = { menu = false; app.open(Screen.Listen) })
            }
        }
    }
    confirmDelete?.let { song ->
        AlertDialog(
            onDismissRequest = { confirmDelete = null },
            title = { Text("Delete “${song.str("title")}”?") },
            text = { Text("Its tones, sections and imported audio file are removed from TonePilot.") },
            confirmButton = { TextButton({ app.command("deleteSong", "id" to song.str("id")); confirmDelete = null }) { Text("Delete", color = Palette.bad) } },
            dismissButton = { TextButton({ confirmDelete = null }) { Text("Cancel") } }
        )
    }
}

@Composable
private fun EmptyLibrary(onImport: () -> Unit, onListen: () -> Unit) {
    Card {
        Text("Bring in a song", fontSize = 20.sp, fontWeight = FontWeight.Bold)
        Text("TonePilot finds the key, tempo, chords, melody and sections, builds a tone for every section, and guides your left hand (Root → Fifth → Root) and right hand.")
        Button(onClick = onImport, modifier = Modifier.fillMaxWidth()) { Text("Import MP3 / audio file") }
        OutlinedButton(onClick = onListen, modifier = Modifier.fillMaxWidth()) { Text("Listen to a song playing in YouTube / Spotify") }
        Caption("Want to just play? Open Play › Choose tone and play any tone from your Casio keys.")
    }
}

@Composable
private fun SongRow(song: JSONObject, onOpen: () -> Unit, onDelete: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(Palette.panel, RoundedCornerShape(12.dp))
            .clickable(onClick = onOpen)
            .padding(start = 14.dp, top = 10.dp, bottom = 10.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(song.str("title"), fontWeight = FontWeight.SemiBold, maxLines = 2)
            val details = listOfNotNull(
                song.str("artist").ifEmpty { null },
                song.str("key").ifEmpty { null },
                song.optInt("bpm", 0).takeIf { it > 0 }?.let { "$it BPM" },
                song.optInt("sections", 0).takeIf { it > 0 }?.let { "$it sections" }
            ).joinToString(" · ")
            Caption(details)
            when (song.str("status")) {
                "running" -> {
                    LinearProgressIndicator(progress = { song.optDouble("progress", 0.0).toFloat() }, modifier = Modifier.fillMaxWidth().padding(top = 4.dp))
                    Caption(song.str("stage").ifEmpty { "Analysing…" })
                }
                "failed" -> Caption(song.str("error").ifEmpty { "Analysis failed" }, Palette.bad)
                "completed" -> Caption("Ready to play", Palette.good)
                else -> {}
            }
        }
        IconButton(onClick = onDelete) { Icon(Icons.Filled.Delete, "Delete", tint = Palette.muted, modifier = Modifier.size(20.dp)) }
    }
}
