package com.tonepilot.app

import android.content.Context
import android.media.midi.MidiDevice
import android.media.midi.MidiDeviceInfo
import android.media.midi.MidiManager
import android.media.midi.MidiOutputPort
import android.media.midi.MidiReceiver
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * USB MIDI from the Casio (or any class-compliant keyboard). Key presses go straight to the
 * Swift engine on Android's MIDI thread; nothing else happens on that path.
 */
class MidiInput(context: Context) {
    private val manager = context.getSystemService(Context.MIDI_SERVICE) as? MidiManager
    private val handler = Handler(Looper.getMainLooper())
    private val open = mutableMapOf<Int, Pair<MidiDevice, List<MidiOutputPort>>>()

    var deviceNames by mutableStateOf(listOf<String>())
        private set
    val supported: Boolean get() = manager != null

    private val receiver = object : MidiReceiver() {
        override fun onSend(msg: ByteArray, offset: Int, count: Int, timestamp: Long) {
            NativeBridge.midi(msg, offset, count)
        }
    }

    private val callback = object : MidiManager.DeviceCallback() {
        override fun onDeviceAdded(device: MidiDeviceInfo) = openDevice(device)
        override fun onDeviceRemoved(device: MidiDeviceInfo) {
            // A cable pulled mid-note never sends note-off: release everything.
            NativeBridge.cmd("panic")
            open.remove(device.id)?.let { (d, ports) -> ports.forEach { runCatching { it.close() } }; runCatching { d.close() } }
            refreshNames()
        }
    }

    fun start() {
        val m = manager ?: return
        m.registerDeviceCallback(callback, handler)
        @Suppress("DEPRECATION")
        m.devices.forEach { openDevice(it) }
    }

    fun rescan() {
        val m = manager ?: return
        @Suppress("DEPRECATION")
        m.devices.filter { it.id !in open }.forEach { openDevice(it) }
    }

    private fun openDevice(info: MidiDeviceInfo) {
        val m = manager ?: return
        if (info.outputPortCount == 0 || open.containsKey(info.id)) return
        m.openDevice(info, { device ->
            if (device == null) return@openDevice
            val ports = (0 until info.outputPortCount).mapNotNull { device.openOutputPort(it) }
            ports.forEach { it.connect(receiver) }
            open[info.id] = device to ports
            refreshNames()
        }, handler)
    }

    private fun refreshNames() {
        deviceNames = open.values.map { (d, _) -> name(d.info) }
    }

    private fun name(info: MidiDeviceInfo): String {
        val p = info.properties
        return p.getString(MidiDeviceInfo.PROPERTY_NAME)
            ?: listOfNotNull(p.getString(MidiDeviceInfo.PROPERTY_MANUFACTURER), p.getString(MidiDeviceInfo.PROPERTY_PRODUCT))
                .joinToString(" ").ifBlank { "MIDI device" }
    }
}
