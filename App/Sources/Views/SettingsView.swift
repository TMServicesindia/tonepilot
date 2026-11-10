import SwiftUI
import TonePilotCore
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var backupURL: URL?

    var body: some View {
        // Spec §2.14: Casio card · Keyboard & audio · Sound · Separation · Storage & about.
        List {
            Section { CasioCard(midi: model.midi) }
            Section("Keyboard & audio") {
                NavigationLink { MIDIDiagnosticsView(midi: model.midi) } label: { SettingsLabel("MIDI and audio check", "cable.connector", DS.Palette.info) }
                NavigationLink { TroubleshootingView() } label: { SettingsLabel("Troubleshooting", "wrench.and.screwdriver", DS.Palette.section[6]) }
                Picker(selection: $model.velocityCurve) {
                    ForEach(VelocityCurve.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                } label: { SettingsLabel("Touch response", "hand.tap", DS.Palette.section[3]) }
            }
            Section {
                Picker(selection: Binding(get: { model.engineKind }, set: { model.setEngine($0) })) {
                    ForEach(EngineKind.allCases) { Text($0.displayName).tag($0) }
                } label: { SettingsLabel("Sound engine", "waveform", DS.Palette.accent) }
                NavigationLink { SoundFontSettingsView() } label: {
                    SettingsLabel("SoundFonts", "music.quarternote.3", DS.Palette.section[1])
                    Spacer()
                    if !model.defaultSoundFontInstalled {
                        Label("Needed", systemImage: "exclamationmark.triangle.fill").font(DS.Text.metadata).foregroundStyle(DS.Palette.warning)
                    }
                }
                NavigationLink { SamplePatchCreatorView() } label: { SettingsLabel("Create a sample instrument", "waveform.badge.plus", DS.Palette.section[2]) }
            } header: { Text("Sound") } footer: {
                Text("The TonePilot engine has every tone control. The Apple sampler is a simpler fallback.")
            }
            SoundPacksSection()
            SeparationModelsSection()
            Section {
                NavigationLink { AnalysisServerSettingsView() } label: {
                    SettingsLabel("Your analysis server", "server.rack", DS.Palette.section[7])
                    Spacer()
                    Text(model.serverSettings.enabled ? "On" : "Off").foregroundStyle(DS.Palette.textSecondary)
                }
                LabeledContent { Text("\(model.library.songs.count)") } label: { SettingsLabel("Songs on this iPhone", "music.note.list", DS.Palette.section[5]) }
                if let backupURL {
                    ShareLink(item: backupURL) { SettingsLabel("Share the backup", "square.and.arrow.up", DS.Palette.success) }
                } else {
                    Button { backupURL = try? model.exportBackup() } label: { SettingsLabel("Back up library and samples", "externaldrive", DS.Palette.success) }
                }
                NavigationLink { LicensesView() } label: { SettingsLabel("Licences and credits", "doc.text", DS.Palette.textTertiary) }
                    .accessibilityIdentifier("settings.licences")
            } header: { Text("Storage & about") } footer: {
                Text("Everything stays on this iPhone (Files › On My iPhone › TonePilot). Audio goes only to an analysis server you set up and switch on.")
            }
        }
        .scrollContentBackground(.hidden)
        .dsCanvas()
        .navigationTitle("Settings")
    }
}

/// A settings row label with a coloured icon square (iOS Settings style).
struct SettingsLabel: View {
    let title: String
    let symbol: String
    let color: Color
    init(_ title: String, _ symbol: String, _ color: Color) { self.title = title; self.symbol = symbol; self.color = color }

    var body: some View {
        Label {
            Text(title).foregroundStyle(DS.Palette.textPrimary)
        } icon: {
            Image(systemName: symbol).font(DS.Text.metadata.weight(.semibold))
                .foregroundStyle(DS.Palette.onAccent)
                .frame(width: DS.Space.xl + DS.Space.xs, height: DS.Space.xl + DS.Space.xs)
                .background(color, in: RoundedRectangle(cornerRadius: DS.Radius.s - DS.Space.xxs, style: .continuous))
        }
    }
}

/// The Casio at the top of Settings: is it connected, and the way to set it up.
struct CasioCard: View {
    @ObservedObject var midi: MIDIInputManager

    var body: some View {
        let casio = midi.sources.first { $0.looksLikeCasio }
        let name = casio?.name ?? midi.sources.first?.name
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.m) {
                InstrumentTile(drawing: .piano, size: 56)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Casio CT-X870IN").font(DS.Text.section).foregroundStyle(DS.Palette.textPrimary)
                    DSChip(text: name.map { "Connected · \($0)" } ?? "Not connected",
                           symbol: name == nil ? "pianokeys" : "checkmark.circle.fill",
                           tone: name == nil ? .accent : .success)
                }
            }
            NavigationLink { ConnectionGuideView() } label: {
                Text(name == nil ? "Set up the Casio" : "Connection guide").font(DS.Text.body.weight(.semibold)).foregroundStyle(DS.Palette.accent)
            }
            .accessibilityIdentifier("settings.casio")
        }
        .padding(.vertical, DS.Space.xs)
    }
}

struct MIDIDiagnosticsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var midi: MIDIInputManager

    var body: some View {
        List {
            Section("MIDI inputs") {
                if midi.sources.isEmpty {
                    Label("No MIDI device detected", systemImage: "exclamationmark.triangle").foregroundStyle(DS.Palette.warning)
                    Text("Connect the Casio's USB TO HOST port to the iPhone with an Apple USB camera adapter (Lightning) or a USB-C to USB-B cable, and switch the keyboard on.")
                        .font(DS.Text.caption)
                }
                ForEach(midi.sources) { s in
                    HStack {
                        Image(systemName: s.looksLikeCasio ? "pianokeys" : "cable.connector")
                        VStack(alignment: .leading) {
                            Text(s.name)
                            if let m = s.manufacturer { Text(m).font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary) }
                        }
                    }
                }
                if let e = midi.setupError { Text(e).foregroundStyle(DS.Palette.error) }
                Button("Rescan devices") { midi.refreshSources() }
            }
            Section("Audio output") {
                Text(model.output.routeDescription).font(DS.Text.caption)
                OutputMeter()
                if model.patchLoadErrors.isEmpty == false {
                    ForEach(model.patchLoadErrors, id: \.self) { Text($0).font(DS.Text.caption).foregroundStyle(DS.Palette.error) }
                }
                Button("All notes off") { model.panic() }
                Text("Held notes: \(model.router.heldNoteCount)").font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
            }
            Section {
                AuditionStrip()
            } footer: { Text("If the audition plays but the Casio keys don't, the problem is the MIDI connection. If neither is audible through the Casio, check the audio cable into AUDIO IN.") }
            Section {
                ForEach(Array(midi.activity.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced())
                }
            } header: {
                HStack { Text("Incoming MIDI"); Spacer(); Button("Clear") { midi.clearLog() }.font(DS.Text.metadata) }
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
                if model.installedSoundFonts.isEmpty { Text("None installed").foregroundStyle(DS.Palette.textSecondary) }
                ForEach(model.installedSoundFonts, id: \.self) { name in
                    HStack {
                        Text(name)
                        if name == FactoryPatches.defaultSoundFontFile { Spacer(); Text("Default").font(DS.Text.metadata).foregroundStyle(DS.Palette.success) }
                    }
                }
                Button { importing = true } label: { Label("Import .sf2 / .dls from Files", systemImage: "square.and.arrow.down") }
                if let error { Text(error).foregroundStyle(DS.Palette.error) }
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
                    .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
            }
            Section("2 · Audio: iPhone → Casio speakers (the sound)") {
                Text("MIDI carries no audio. TonePilot's sound comes out of the iPhone's audio output, so it needs a second cable into the Casio's AUDIO IN (3.5 mm stereo mini jack).")
                Text("USB-C iPhones: a USB-C hub with a USB-A port (for the Casio) and a 3.5 mm jack. Lightning iPhones: the single port is taken by the camera adapter, so put a powered USB hub on the adapter and connect both the Casio and a small class-compliant USB audio interface or USB DAC. Avoid Bluetooth audio — it adds 100–200 ms delay.")
                Text("Cable: 3.5 mm stereo male to 3.5 mm stereo male, from the headphone/line output into AUDIO IN. Start with iPhone volume around 60% and raise it until the sound is clear without distortion.")
                    .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
            }
            Section("3 · Avoid hearing the Casio's own voice too") {
                Text("Turn the Casio's main/tone volume down, or set Local Control off in the keyboard's MIDI settings if your model offers it. AUDIO IN playback keeps working, so you hear only TonePilot.")
                Text("Check your keyboard's manual for the exact menu — the steps differ between Casio models.")
                    .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
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
                Text(item.0).font(DS.Text.section)
                Text(item.1).font(DS.Text.bodySecondary).foregroundStyle(DS.Palette.textSecondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Troubleshooting")
    }
}

/// One bundled licence text (App/Resources/Licenses), shown in full.
struct LicenseText: View {
    let file: String
    static var bundled: [String] {
        guard let dir = Bundle.main.url(forResource: "Licenses", withExtension: nil),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) }.sorted()
    }
    var body: some View {
        let url = Bundle.main.url(forResource: "Licenses", withExtension: nil)?.appendingPathComponent(file + ".txt")
        ScrollView {
            Text(url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Licence text missing.")
                .font(.caption.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle(file)
        .accessibilityIdentifier("licenses.text")
    }
}

struct LicensesView: View {
    var body: some View {
        List {
            Section("Sounds") {
                Text("General MIDI presets reference GeneralUser GS by S. Christian Collins (GeneralUser GS License v2.0) when installed. The author notes sample origins can't be 100% verified; review before commercial distribution.")
            }
            Section("On-device analysis & sound") {
                Text("Implemented in TonePilotCore (this project) from published methods: Ellis 2007 beat tracking, Krumhansl–Kessler key profiles, Foote 2000 novelty segmentation, Salamon & Gómez 2012-style predominant melody, Freeverb (public domain) reverb.")
            }
            Section("Nearest-sound search") {
                Text("Finding the nearest tone for each separated part uses EfficientAT mn10 (MIT, Florian Schmid, github.com/fschmid56/EfficientAT), converted to Core ML and run on this iPhone. Its pretrained weights were trained on Google AudioSet; AudioSet label names are CC BY-SA 4.0.")
            }
            Section("Real instrument sounds") {
                Text("Downloadable sound packs are built from VSCO 2 Community Edition (Sam Gossner and contributors, github.com/sgossner/VSCO-2-CE) and the Versilian Community Sample Library (github.com/sgossner/VCSL), both released under CC0 1.0 (public domain). Each pack lists every original file it uses.")
            }
            Section("Separation & recording") {
                Text("Stem separation on this iPhone: Demucs v4 htdemucs / htdemucs_6s (MIT, Meta AI) via demucs.cpp (MIT, Sevag Hanssian) and Eigen (MPL-2.0); models are downloaded in the app.")
                Text("MP3 export (Record): LAME 3.100 (GNU LGPL 2.0, lame.sourceforge.io). TonePilot's full source, including how LAME is built, is public, so it can be rebuilt with a modified LAME.")
            }
            Section("Full licence texts") {
                ForEach(LicenseText.bundled, id: \.self) { name in
                    NavigationLink(name) { LicenseText(file: name) }
                        .accessibilityIdentifier("licenses.full.\(name)")
                }
            }
            Section("Optional analysis server") {
                Text("Demucs (MIT, github.com/adefossez/demucs) for stem separation and Spotify Basic Pitch (Apache-2.0, github.com/spotify/basic-pitch) for vocal transcription run on your own Mac/server — not bundled in the app.")
            }
        }
        .navigationTitle("Licenses")
    }
}

/// First run (spec §2.1): two steps to the first song. 1 · Welcome + connect the Casio. 2 · Import a song.
struct SetupWizardView: View {
    @EnvironmentObject var model: AppModel
    let onDone: () -> Void
    @State private var step = 0
    @State private var guide = false
    @State private var pickSong = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                Spacer(minLength: DS.Space.l)
                if step == 0 { welcome } else { ready }
                Spacer()
                Text("Step \(step + 1) of 2").font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(DS.Space.xl)
            .dsCanvas()
            .navigationDestination(isPresented: $guide) { ConnectionGuideView() }
            .fileImporter(isPresented: $pickSong, allowedContentTypes: [.mp3, .mpeg4Audio, .wav, .aiff, .audio]) { result in
                if case .success(let url) = result, let id = model.importAndAnalyze(from: url) {
                    onDone()
                    model.openStudio(id)
                }
            }
        }
    }

    @ViewBuilder private var welcome: some View {
        let connected = !model.midi.sources.isEmpty
        InstrumentTile(drawing: .piano, size: 96)
        Text("Welcome to TonePilot").font(DS.Text.largeTitle).foregroundStyle(DS.Palette.textPrimary)
        Text("Play film-song tones on your Casio.").font(DS.Text.body).foregroundStyle(DS.Palette.textSecondary)
        if connected {
            DSChip(text: "Casio connected", symbol: "checkmark.circle.fill", tone: .success)
            Button("Continue") { step = 1 }.buttonStyle(.dsPrimary).accessibilityIdentifier("setup.continue")
        } else {
            Button("Connect your Casio") { guide = true }.buttonStyle(.dsPrimary).accessibilityIdentifier("setup.connect")
            Button("Later") { step = 1 }.buttonStyle(.dsSecondary).accessibilityIdentifier("setup.later")
        }
    }

    @ViewBuilder private var ready: some View {
        InstrumentTile(drawing: .voice, size: 96)
        Text("Add your first song").font(DS.Text.largeTitle).foregroundStyle(DS.Palette.textPrimary)
        Text("Import a song you own. TonePilot finds its sections, chords and tones on this iPhone.")
            .font(DS.Text.body).foregroundStyle(DS.Palette.textSecondary)
        if !model.defaultSoundFontInstalled {
            NavigationLink { SoundFontSettingsView() } label: {
                Label("Add the free SoundFont for the built-in sounds", systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Text.caption).foregroundStyle(DS.Palette.warning)
            }
            .accessibilityIdentifier("setup.soundfont")
        }
        Button("Import a song") { pickSong = true }.buttonStyle(.dsPrimary).accessibilityIdentifier("setup.import")
        Button("Explore first") { onDone() }.buttonStyle(.dsSecondary).accessibilityIdentifier("setup.explore")
    }
}


struct AnalysisServerSettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var token = ""
    @State private var status: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                Toggle("Use my analysis server", isOn: $model.serverSettings.enabled)
                TextField("http://192.168.1.20:8765", text: $model.serverSettings.baseURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Access token", text: $token)
                    .onSubmit { model.serverToken = token }
                Picker("Separation model", selection: $model.serverSettings.model) {
                    Text("htdemucs · vocals/drums/bass/other").tag("htdemucs")
                    Text("htdemucs_6s · + piano/guitar (weaker)").tag("htdemucs_6s")
                }
                Toggle("Transcribe vocal melody (Basic Pitch)", isOn: $model.serverSettings.transcribeVocals)
            } footer: {
                Text("Run the server from the project's server/ folder on your Mac (see server/README.md). While this is on, every imported song is sent to this server for vocal separation and deleted there after the results download. Turn it off to analyse on the iPhone only. The token is stored in the iPhone Keychain.")
            }
            Section {
                Button(testing ? "Testing…" : "Test connection") {
                    model.serverToken = token
                    testing = true
                    Task { status = await model.testServer(); testing = false }
                }
                .disabled(testing)
                if let status { Text(status).font(DS.Text.caption) }
            }
        }
        .navigationTitle("Analysis server")
        .onAppear { token = model.serverToken ?? "" }
        .onDisappear { model.serverToken = token }
    }
}


/// Separation models: downloaded inside the app when first needed; size and delete here.
struct SeparationModelsSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section {
            ForEach(SeparationPack.allCases) { pack in
                let installed = model.models.isInstalled(pack)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(pack.title).font(DS.Text.label)
                        if model.separationPack == pack { StatusPill(text: "Used", color: DS.Palette.accent) }
                        Spacer()
                        if let p = model.modelDownloadProgress[pack] {
                            ProgressView(value: p).frame(width: 80)
                        } else if installed {
                            Text(ByteCountFormatter.string(fromByteCount: model.models.installedSize(pack), countStyle: .file))
                                .font(.caption.monospacedDigit()).foregroundStyle(DS.Palette.textSecondary)
                            Button(role: .destructive) { model.deleteModel(pack) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).accessibilityLabel("Delete \(pack.title) model")
                        } else {
                            Button("Download") { model.downloadModel(pack) }.buttonStyle(.bordered)
                        }
                    }
                    Text(pack.detail).font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                }
            }
            if let e = model.modelDownloadError { Text(e).font(DS.Text.metadata).foregroundStyle(DS.Palette.error) }
            Toggle(isOn: $model.fusionEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check tones with both models")
                    Text("Surer tones. Takes about twice as long.")
                        .font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .accessibilityIdentifier("settings.fusion")
        } header: {
            Text("Parts (4 or 6)")
        } footer: {
            Text("Downloads when first needed (Wi-Fi recommended). Delete one to free space.")
        }
    }
}


/// Real-instrument sound packs (CC0 recordings): download / delete. Installed packs' tones appear in
/// the tone library and in the nearest-sound search.
struct SoundPacksSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section {
            if model.soundPackList.isEmpty && model.installedSoundPacks.isEmpty {
                Text(model.soundPackError == nil ? "Checking for sound packs…" : "Sound packs aren't available right now.")
                    .font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
            }
            ForEach(model.soundPackList) { pack in
                let installed = model.installedSoundPacks.contains(pack.id)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(pack.name).font(DS.Text.label)
                        if installed { StatusPill(text: "Installed", color: DS.Palette.accent) }
                        Spacer()
                        if let p = model.soundPackProgress[pack.id] {
                            ProgressView(value: p).frame(width: 80)
                        } else if installed, (model.installedSoundPackVersions[pack.id] ?? pack.version) < pack.version {
                            Button("Update") { model.downloadSoundPack(pack) }
                                .buttonStyle(.bordered).accessibilityIdentifier("soundpacks.update.\(pack.id)")
                        } else if installed {
                            Text(ByteCountFormatter.string(fromByteCount: model.soundPacks.installedSize(pack.id), countStyle: .file))
                                .font(.caption.monospacedDigit()).foregroundStyle(DS.Palette.textSecondary)
                            Button(role: .destructive) { model.deleteSoundPack(pack.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).accessibilityLabel("Delete \(pack.name)")
                                .accessibilityIdentifier("soundpacks.delete.\(pack.id)")
                        } else {
                            Button("Download \(ByteCountFormatter.string(fromByteCount: pack.size, countStyle: .file))") { model.downloadSoundPack(pack) }
                                .buttonStyle(.bordered).accessibilityIdentifier("soundpacks.download.\(pack.id)")
                        }
                    }
                    Text(pack.tones.joined(separator: ", ")).font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                }
                .accessibilityIdentifier("soundpacks.row.\(pack.id)")
            }
            if let e = model.soundPackError { Text(e).font(DS.Text.metadata).foregroundStyle(DS.Palette.error) }
        } header: {
            Text("Real instrument sounds").accessibilityIdentifier("settings.soundpacks")
        } footer: {
            Text("Free, public-domain recordings (VSCO, VCSL). They join the closest-sound search. Wi-Fi recommended.")
        }
        .onAppear { if model.soundPackList.isEmpty { model.loadSoundPackList() } }
    }
}

