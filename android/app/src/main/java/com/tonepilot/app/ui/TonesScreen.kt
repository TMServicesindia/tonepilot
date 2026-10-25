package com.tonepilot.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tonepilot.app.AppState
import com.tonepilot.app.NativeBridge
import com.tonepilot.app.objects
import com.tonepilot.app.str
import org.json.JSONObject

/**
 * Pick a tone and play it from the Casio keys — like the keyboard's own TONE button, but with
 * TonePilot's tones: AI-built song tones, your saved tones, and every instrument.
 */
@Composable
fun TonesScreen(app: AppState) {
    var search by remember { mutableStateOf("") }
    val list = remember(search, app.revision) { NativeBridge.cmd("tones", "search" to search) }
    LazyColumn(Modifier.fillMaxSize().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        item {
            OutlinedTextField(value = search, onValueChange = { search = it }, singleLine = true,
                leadingIcon = { Icon(Icons.Filled.Search, null) }, placeholder = { Text("Search tones") },
                modifier = Modifier.fillMaxWidth().padding(bottom = 6.dp))
            Caption("Now playing: ${app.state.str("toneName")}", Palette.accent)
        }
        for (group in list.objects("groups")) {
            item(key = "h-" + group.str("title")) { Box(Modifier.padding(top = 10.dp)) { SectionLabel(group.str("title")) } }
            val entries = group.objects("entries")
            if (entries.isEmpty() && group.str("kind") == "mine") item { Caption("Save any tone here with ⋮ › Save to My Tones.") }
            items(entries, key = { group.str("kind") + it.str("id") }) { entry -> ToneRow(app, entry, canSave = group.str("kind") != "mine") }
        }
        item { Box(Modifier.padding(16.dp)) }
    }
}

@Composable
private fun ToneRow(app: AppState, entry: JSONObject, canSave: Boolean) {
    var menu by remember { mutableStateOf(false) }
    val active = entry.optBoolean("active")
    Row(
        Modifier.fillMaxWidth()
            .background(if (active) Palette.raised else Palette.panel, RoundedCornerShape(10.dp))
            .clickable { app.command("activateTone", "id" to entry.str("id")) }
            .padding(start = 12.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(entry.str("name"), fontWeight = if (active) FontWeight.Bold else FontWeight.Normal, color = if (active) Palette.accent else Color.Unspecified)
            Caption(entry.str("subtitle"))
        }
        if (canSave) Box {
            IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, "More") }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("Save to My Tones") }, onClick = {
                    menu = false
                    val r = app.command("saveToMyTones", "id" to entry.str("id"))
                    if (r.optBoolean("ok")) app.toast = "Saved “${r.str("name")}” to My Tones"
                })
            }
        }
    }
}
