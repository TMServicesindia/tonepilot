@file:OptIn(ExperimentalMaterial3Api::class)

package com.tonepilot.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.tonepilot.app.AppState
import com.tonepilot.app.Screen
import kotlinx.coroutines.delay

@Composable
fun TonePilotRoot(app: AppState) {
    MaterialTheme(colorScheme = TonePilotColors) {
        if (!app.started) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator()
                    Text(app.preparing, modifier = Modifier.padding(top = 16.dp))
                }
            }
            return@MaterialTheme
        }
        BackHandler(enabled = app.stack.size > 1) { app.back() }
        val screen = app.current
        val isTab = screen == Screen.Library || screen == Screen.Play || screen == Screen.Settings
        Scaffold(
            containerColor = Palette.background,
            topBar = {
                TopAppBar(
                    title = { Text(title(screen)) },
                    navigationIcon = {
                        if (!isTab) IconButton(onClick = { app.back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = Palette.background)
                )
            },
            bottomBar = {
                NavigationBar(containerColor = Palette.panel) {
                    val tabRoot = app.stack.first()
                    NavigationBarItem(selected = tabRoot == Screen.Library, onClick = { app.tab(Screen.Library) },
                        icon = { Icon(Icons.AutoMirrored.Filled.List, null) }, label = { Text("Library") })
                    NavigationBarItem(selected = tabRoot == Screen.Play, onClick = { app.tab(Screen.Play) },
                        icon = { Icon(Icons.Filled.PlayArrow, null) }, label = { Text("Play") })
                    NavigationBarItem(selected = tabRoot == Screen.Settings, onClick = { app.tab(Screen.Settings) },
                        icon = { Icon(Icons.Filled.Settings, null) }, label = { Text("Settings") })
                }
            }
        ) { padding ->
            Box(Modifier.padding(padding).fillMaxSize()) {
                when (screen) {
                    Screen.Library -> LibraryScreen(app)
                    Screen.Play -> PlayScreen(app)
                    Screen.Settings -> SettingsScreen(app)
                    is Screen.Song -> SongScreen(app, screen.id)
                    is Screen.SectionGuide -> SectionGuideScreen(app, screen.songId, screen.sectionId)
                    Screen.Tones -> TonesScreen(app)
                    Screen.Listen -> ListenScreen(app)
                }
            }
        }
        app.startError?.let { e ->
            AlertDialog(onDismissRequest = { app.startError = null }, confirmButton = { TextButton({ app.startError = null }) { Text("OK") } },
                title = { Text("Audio problem") }, text = { Text(e) })
        }
        app.toast?.let { msg ->
            LaunchedEffect(msg) { delay(3500); app.toast = null }
            Box(Modifier.fillMaxSize().padding(bottom = 96.dp), contentAlignment = Alignment.BottomCenter) {
                Text(msg, modifier = Modifier
                    .padding(16.dp)
                    .then(Modifier), color = Palette.warn)
            }
        }
    }
}

private fun title(s: Screen): String = when (s) {
    Screen.Library -> "TonePilot"
    Screen.Play -> "Play on My Casio"
    Screen.Settings -> "Settings"
    is Screen.Song -> "Song"
    is Screen.SectionGuide -> "Section guide"
    Screen.Tones -> "Choose tone"
    Screen.Listen -> "Listen to a song"
}
