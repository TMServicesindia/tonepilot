package com.tonepilot.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tonepilot.app.AppState
import com.tonepilot.app.BuildConfigInfo
import com.tonepilot.app.NativeBridge
import com.tonepilot.app.str
import com.tonepilot.app.strings

@Composable
fun SettingsScreen(app: AppState) {
    val st = app.state
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {

        Card("Connect your Casio CT-X870IN") {
            Text("1. Keys → phone: connect the Casio's USB TO HOST port (USB-B) to the phone with a USB-C to USB-B cable, or a USB-A to USB-B cable plus a USB-C OTG adapter. Switch the keyboard on.")
            Text("2. Sound → Casio: TonePilot's sound comes out of the phone. Connect the phone's 3.5 mm headphone jack to the Casio's AUDIO IN with a 3.5 mm stereo male-to-male cable. If the phone has no headphone jack, use a USB-C hub with a USB port and a 3.5 mm jack (or a USB-C audio adapter in the hub).")
            Text("3. Turn the Casio's own volume down or set Local Control off (if your model has it) so you hear only TonePilot. Start with the phone volume around 60%.")
            Caption("Avoid Bluetooth speakers/headphones for playing: they add 100–200 ms delay.")
        }

        Card("MIDI") {
            val devices = app.midi.deviceNames
            if (!app.midi.supported) Text("This phone doesn't support USB MIDI.", color = Palette.bad)
            else if (devices.isEmpty()) Text("No MIDI keyboard detected", color = Palette.warn)
            else devices.forEach { Text("● $it", color = Palette.good) }
            OutlinedButton(onClick = { app.midi.rescan() }) { Text("Scan again") }
            Caption("Messages received: ${st.optInt("midiCount")}. Press a Casio key and watch for “Note On”.")
            st.strings("midiLog").forEach { Text(it, fontFamily = FontFamily.Monospace, fontSize = 12.sp) }
        }

        Card("Audio output") {
            val status = remember(app.revision) { NativeBridge.audioStatus() }
            InfoRow("Output", app.outputDescription())
            InfoRow("Stream", status)
            InfoRow("Voices", st.optInt("voices").toString())
            if (app.isPhoneSpeaker()) Caption("Sound is going to the phone speaker, not the Casio.", Palette.warn)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { NativeBridge.restartAudio(); app.refresh() }) { Text("Restart audio") }
                OutlinedButton(onClick = { NativeBridge.cmd("panic") }) { Text("All notes off") }
            }
            Caption("If you plug the cable or hub in while TonePilot is open and hear nothing, tap Restart audio.")
            AuditionStrip()
        }

        Card("Sounds") {
            InfoRow("SoundFont", if (st.optBoolean("soundFontReady")) "GeneralUser GS (bundled) ✓" else "Loading…")
            Caption("Instrument sounds: GeneralUser GS by S. Christian Collins, used under its licence (free to use in apps). Synthesized leads (vocal-like lead, soft synth, pad, pluck) are TonePilot's own.")
        }

        Card("Privacy") {
            Caption("Everything stays on this phone. Songs are analysed on the phone; Listen Mode audio is kept in memory only and discarded after analysis. Deleting a song also deletes its imported audio copy.")
        }

        Card("About") {
            InfoRow("Version", BuildConfigInfo.versionName)
            Caption(st.str("error"), Palette.bad)
        }
        Box(Modifier.height(24.dp))
    }
}
