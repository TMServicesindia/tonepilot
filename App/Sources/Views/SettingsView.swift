import SwiftUI
import TonePilotCore
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List {
            Section("Keyboard & audio") {
                NavigationLink { MIDIDiagnosticsView(midi: model.midi) } label: { Label("MIDI & audio diagnostics", systemImage: "cable.connector") }
                NavigationLink { ConnectionGuideView() } label: { Label("Connect your Casio CT-X870IN", systemImage: "pianokeys") }
                NavigationLink { TroubleshootingView() } label: { Label("Troubleshooting", systemImage: "wrench.and.screwdriver") }
                Picker("Velocity curve", selection: $model.velocityCurve) {
                    ForEach(VelocityCurve.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
            }
            Section("Sounds") {
                NavigationLink { SoundFontSettingsView() } label: {
                    Label("SoundFonts", systemImage: "music.quarternote.3")
                    Spacer()
                    if !model.defaultSoundFontInstalled { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn) }
                }
            }
            Section("Your data") {
                LabeledContent("Songs", value: "\(model.library.songs.count)")
                LabeledContent("Storage", value: model.store.rootDirectory.lastPathComponent)
                Text("Everything is stored on this iPhone (Files › On My iPhone › TonePilot). Audio is analysed on-device and never uploaded. Deleting a song also deletes its imported audio.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("About") {
                NavigationLink("Licenses & credits") { LicensesView() }
            }
        }
        .navigationTitle("Settings")
    }
}

struct MIDIDiagnosticsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var midi: MIDIInputManager

    var body: some View {
        List {
            Section("MIDI inputs") {
                if midi.sources.isEmpty {
                    Label("No MIDI device detected", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warn)
                    Text("Connect the Casio's USB TO HOST port to the iPhone with an Apple USB camera adapter (Lightning) or a USB-C to USB-B cable, and switch the keyboard on.")
                        .font(.footnote)
                }
                ForEach(midi.sources) { s in
                    HStack {
                        Image(systemName: s.looksLikeCasio ? "pianokeys" : "cable.connector")
                        VStack(alignment: .leading) {
                            Text(s.name)
                            if let m = s.manufacturer { Text(m).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                if let e = midi.setupError { Text(e).foregroundStyle(Theme.bad) }
                Button("Rescan devices") { midi.refreshSources() }
            }
            Section("Audio output") {
                Text(model.engine.routeDescription).font(.footnote)
                OutputMeter()
                if model.patchLoadErrors.isEmpty == false {
                    ForEach(model.patchLoadErrors, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.bad) }
                }
                Button("All notes off") { model.panic() }
                Text("Held notes: \(model.router.heldNoteCount)").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                AuditionStrip()
            } footer: { Text("If the audition plays but the Casio keys don't, the problem is the MIDI connection. If neither is audible through the Casio, check the audio cable into AUDIO IN.") }
            Section {
                ForEach(Array(midi.activity.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced())
                }
            } header: {
                HStack { Text("Incoming MIDI"); Spacer(); Button("Clear") { midi.clearLog() }.font(.caption) }
            }
        }
        .navigationTitle("Diagnostics")
    }
}

struct SoundFontSettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                if model.installedSoundFonts.isEmpty { Text("None installed").foregroundStyle(.secondary) }
                ForEach(model.installedSoundFonts, id: \.self) { name in
                    HStack {
                        Text(name)
                        if name == FactoryPatches.defaultSoundFontFile { Spacer(); Text("Default").font(.caption).foregroundStyle(Theme.good) }
                    }
                }
                Button { importing = true } label: { Label("Import .sf2 / .dls from Files", systemImage: "square.and.arrow.down") }
                if let error { Text(error).foregroundStyle(Theme.bad) }
            } footer: {
                Text("The built-in sounds use General MIDI presets from \(FactoryPatches.defaultSoundFontFile). If it is missing, every layer will be silent or play a plain sine tone. Download GeneralUser GS (free, by S. Christian Collins) from github.com/mrbumpy409/GeneralUser-GS, rename the .sf2 to \(FactoryPatches.defaultSoundFontFile), and import it here.")
            }
        }
        .navigationTitle("SoundFonts")
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "sf2") ?? .data, UTType(filenameExtension: "dls") ?? .data]) { result in
            do { try model.importSoundFont(from: result.get()) } catch { self.error = error.localizedDescription }
        }
    }
}

struct ConnectionGuideView: View {
    var body: some View {
        List {
            Section("1 · MIDI: Casio → iPhone (your playing)") {
                Text("Casio USB TO HOST (USB-B) → USB-A-to-B cable → Apple Lightning to USB 3 Camera Adapter → iPhone. On USB-C iPhones use a USB-C to USB-B cable.")
                Text("The Lightning USB 3 adapter has a charging port — plug in power if the keyboard isn't detected; the phone may not supply enough power.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("2 · Audio: iPhone → Casio speakers (the sound)") {
                Text("MIDI carries no audio. TonePilot's sound comes out of the iPhone's audio output, so it needs a second cable into the Casio's AUDIO IN (3.5 mm stereo mini jack).")
                Text("USB-C iPhones: a USB-C hub with a USB-A port (for the Casio) and a 3.5 mm jack. Lightning iPhones: the single port is taken by the camera adapter, so put a powered USB hub on the adapter and connect both the Casio and a small class-compliant USB audio interface or USB DAC. Avoid Bluetooth audio — it adds 100–200 ms delay.")
                Text("Cable: 3.5 mm stereo male to 3.5 mm stereo male, from the headphone/line output into AUDIO IN. Start with iPhone volume around 60% and raise it until the sound is clear without distortion.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("3 · Avoid hearing the Casio's own voice too") {
                Text("Turn the Casio's main/tone volume down, or set Local Control off in the keyboard's MIDI settings if your model offers it. AUDIO IN playback keeps working, so you hear only TonePilot.")
                Text("Check your keyboard's manual for the exact menu — the steps differ between Casio models.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("4 · Test") {
                Text("Settings › MIDI & audio diagnostics: press a key and watch for 'Note On'. Then tap the audition keys: if you hear them through the Casio, the audio path works.")
            }
        }
        .navigationTitle("Casio CT-X870IN setup")
    }
}

struct TroubleshootingView: View {
    private let items: [(String, String)] = [
        ("MIDI device not detected", "Use Apple's USB camera adapter (cheap passive OTG cables don't enable USB host mode). Power the adapter. Turn the Casio off and on. Tap Rescan in Diagnostics."),
        ("MIDI notes arrive but no sound", "Install the default SoundFont (Settings › SoundFonts). Check the active tone has unmuted layers whose key range covers the keys you play. Check the iPhone's volume and silent mode."),
        ("Sound plays on the iPhone, not the Casio", "MIDI doesn't carry audio. Connect the iPhone's audio output to the Casio's AUDIO IN with a 3.5 mm stereo cable, and check the output shown in Diagnostics."),
        ("Latency / delay", "Use a wired connection (no Bluetooth audio). Close other audio apps. Diagnostics shows the measured output latency; under ~15 ms feels immediate."),
        ("Distortion or clipping", "Watch the CLIP light. Lower Master or layer volumes, or the iPhone volume, rather than turning the Casio up. Many stacked loud layers add up quickly."),
        ("Stuck or sustained notes", "Press PANIC (Performance) or All notes off (Diagnostics). Unplugging the keyboard releases all notes automatically."),
    ]

    var body: some View {
        List(items, id: \.0) { item in
            VStack(alignment: .leading, spacing: 6) {
                Text(item.0).font(.headline)
                Text(item.1).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Troubleshooting")
    }
}

struct LicensesView: View {
    var body: some View {
        List {
            Section("Sounds") {
                Text("General MIDI presets reference GeneralUser GS by S. Christian Collins (GeneralUser GS License v2.0) when installed. The author notes sample origins can't be 100% verified; review before commercial distribution.")
            }
            Section("Analysis") {
                Text("Tempo, key, chord and structure analysis are implemented in TonePilotCore (this project) using published methods: Ellis 2007 beat tracking, Krumhansl–Kessler key profiles, Foote 2000 novelty segmentation.")
            }
            Section("Planned (not included yet)") {
                Text("Demucs (MIT) for stem separation and Spotify Basic Pitch (Apache-2.0) for note transcription, run on a Mac/server or as Core ML models after license and size review.")
            }
        }
        .navigationTitle("Licenses")
    }
}

struct SetupWizardView: View {
    @EnvironmentObject var model: AppModel
    let onDone: () -> Void
    @State private var step = 0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                switch step {
                case 0:
                    Text("Welcome to TonePilot").font(.largeTitle.bold())
                    Text("Play film-song tones — layered piano, strings, bells, pads — from your Casio's keys, with the sound coming from this iPhone through the Casio's speakers.")
                    Text("Import songs you own as MP3s and TonePilot analyses them on-device to help you build a tone for each intro, interlude and chorus.")
                        .foregroundStyle(.secondary)
                case 1:
                    Text("Install sounds").font(.title.bold())
                    if model.defaultSoundFontInstalled {
                        Label("Default SoundFont installed", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
                    } else {
                        Text("TonePilot needs a General MIDI SoundFont for its built-in sounds. Get GeneralUser GS (free) and import it.")
                        NavigationLink("Open SoundFonts") { SoundFontSettingsView() }
                    }
                default:
                    Text("Connect your keyboard").font(.title.bold())
                    ConnectionStatus(midi: model.midi)
                    Text("1. Casio USB TO HOST → iPhone (USB camera adapter) for MIDI.\n2. iPhone audio output → Casio AUDIO IN (3.5 mm cable) for sound.")
                    NavigationLink("Full connection guide") { ConnectionGuideView() }
                    AuditionStrip()
                }
                Spacer()
                HStack {
                    if step > 0 { Button("Back") { step -= 1 } }
                    Spacer()
                    Button(step == 2 ? "Start" : "Next") { if step == 2 { onDone() } else { step += 1 } }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
    }
}
