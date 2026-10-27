import SwiftUI
import TonePilotCore

/// Tone Studio tab: every saved composite tone, global or per song.
struct ToneStudioHomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: (songId: UUID?, arrangementId: UUID)?
    @State private var showEditor = false
    @State private var importingPresets = false
    @State private var showSampleCreator = false
    @State private var importMessage: String?

    var body: some View {
        List {
            if let importMessage { Text(importMessage).font(.footnote).foregroundStyle(.secondary) }
            Section {
                NavigationLink { ToneSelectorView() } label: { Label("Choose a tone to play", systemImage: "pianokeys") }
            }
            Section {
                ForEach(model.library.globalArrangements) { a in row(a, songId: nil) }
                Button {
                    let a = Arrangement.starterFilmStack(name: "My tone \(model.library.globalArrangements.count + 1)")
                    model.updateArrangement(a, inSong: nil)
                    open(nil, a.id)
                } label: { Label("New tone", systemImage: "plus") }
            } header: { Text("My tones") } footer: {
                Text("Tones here aren't tied to a song. Song tones live inside each song.")
            }
            ForEach(model.library.songs.filter { !$0.arrangements.isEmpty }) { song in
                Section(song.title) {
                    ForEach(song.arrangements.filter { $0.origin != .aiOriginal }) { a in row(a, songId: song.id) }
                }
            }
        }
        .navigationTitle("Tone Studio")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { ConnectionStatus(midi: model.midi) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { importingPresets = true } label: { Label("Import presets…", systemImage: "square.and.arrow.down") }
                    Button { showSampleCreator = true } label: { Label("New sample instrument…", systemImage: "waveform.badge.plus") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .fileImporter(isPresented: $importingPresets, allowedContentTypes: [.json]) { result in
            do {
                let missing = try model.importPresets(from: result.get())
                importMessage = missing.isEmpty ? "Presets imported." : "Imported. Provide these samples to hear every layer: \(missing.joined(separator: ", "))"
            } catch { importMessage = "That file isn't a TonePilot preset." }
        }
        .navigationDestination(isPresented: $showSampleCreator) { SamplePatchCreatorView() }
        .navigationDestination(isPresented: $showEditor) {
            if let e = editing { ArrangementEditorView(songId: e.songId, arrangementId: e.arrangementId) }
        }
    }

    private func open(_ songId: UUID?, _ id: UUID) {
        editing = (songId, id)
        showEditor = true
    }

    private func row(_ a: Arrangement, songId: UUID?) -> some View {
        Button { open(songId, a.id) } label: {
            HStack {
                VStack(alignment: .leading) {
                    HStack(spacing: 6) {
                        Text(a.name).font(.headline)
                        if a.origin == .myVersion { Text("AI-built").font(.caption2).padding(.horizontal, 5).background(Theme.accent.opacity(0.25), in: Capsule()) }
                    }
                    Text("\(a.layers.count) layer\(a.layers.count == 1 ? "" : "s") · " +
                         a.layers.compactMap { model.library.patch(id: $0.patchId)?.name }.joined(separator: " + "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if model.activeArrangement?.id == a.id { Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.accent) }
            }
        }
        .foregroundStyle(.primary)
    }
}

/// Edits one composite tone. Every change is applied live, so you hear it on the Casio while editing.
struct ArrangementEditorView: View {
    @EnvironmentObject var model: AppModel
    let songId: UUID?
    let arrangementId: UUID
    /// Shown as a sheet: a Done button closes it.
    var onDone: (() -> Void)?
    @State private var expandedLayer: UUID?
    @State private var pickingPatchForLayer: UUID?
    @State private var addingLayer = false
    @State private var exportURL: URL?

    private static let layerColors: [Color] = [.orange, .teal, .purple, .pink, .yellow, .mint]

    private var arrangement: Arrangement? {
        if let songId { return model.song(songId)?.arrangements.first { $0.id == arrangementId } }
        return model.library.globalArrangements.first { $0.id == arrangementId }
    }

    var body: some View {
        if let arrangement {
            Form {
                if arrangement.origin == .aiOriginal {
                    Section {
                        Label("AI Original — kept unchanged so you can always go back.", systemImage: "lock")
                        Text("Edit the section's My Version instead (Song › section ⋯ › Edit tone).").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let rationale = arrangement.rationale {
                    Section("Why the AI built this") { Text(rationale).font(.footnote) }
                }
                Section {
                    TextField("Tone name", text: binding(\.name))
                    HStack {
                        Text("Master")
                        Slider(value: binding(\.masterGain), in: 0...1)
                    }
                    OutputMeter()
                    Button {
                        model.activate(arrangement, songId: songId == model.activeSongId ? songId : nil)
                    } label: {
                        Label(model.activeArrangement?.id == arrangement.id ? "Playing on keyboard" : "Use on keyboard",
                              systemImage: "pianokeys")
                    }
                    .disabled(model.activeArrangement?.id == arrangement.id)
                }

                Section("Keyboard map (61 keys, C2–C7)") {
                    KeyRangePreview(ranges: arrangement.layers.enumerated().filter { $0.element.enabled }
                        .map { ($0.element.keyRange, Self.layerColors[$0.offset % Self.layerColors.count]) })
                }

                Section {
                    ForEach(Array(arrangement.layers.enumerated()), id: \.element.id) { index, layer in
                        LayerEditor(layer: layerBinding(layer.id),
                                    patch: model.library.patch(id: layer.patchId),
                                    color: Self.layerColors[index % Self.layerColors.count],
                                    expanded: expandedLayer == layer.id,
                                    onToggle: { expandedLayer = expandedLayer == layer.id ? nil : layer.id },
                                    onChangePatch: { pickingPatchForLayer = layer.id },
                                    fullControls: model.engineKind == .tonePilot)
                    }
                    .onDelete { offsets in mutate { $0.layers.remove(atOffsets: offsets) } }
                    .onMove { from, to in mutate { $0.layers.move(fromOffsets: from, toOffset: to) } }
                    if arrangement.layers.count < maxLayers {
                        Button { addingLayer = true } label: { Label("Add layer", systemImage: "plus") }
                    } else {
                        Text("Maximum \(maxLayers) layers with this engine.").font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Layers") } footer: {
                    Text("Layers on the same keys sound together. Use key ranges for splits (e.g. bass on the left hand) and velocity ranges to switch sounds by how hard you play.")
                }

                if !model.patchLoadErrors.isEmpty {
                    Section("Problems") {
                        ForEach(model.patchLoadErrors, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.bad) }
                        NavigationLink("Install a SoundFont") { SoundFontSettingsView() }
                    }
                }

                if model.engineKind == .tonePilot { masterSection(arrangement) }

                Section { AuditionStrip() }

                Section {
                    Button { duplicate(arrangement) } label: { Label("Duplicate tone", systemImage: "plus.square.on.square") }
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Share preset file", systemImage: "square.and.arrow.up") }
                    } else {
                        Button { exportURL = try? model.exportPresets([arrangement], name: arrangement.name) } label: { Label("Export preset…", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .disabled(arrangement.origin == .aiOriginal)
            .navigationTitle(arrangement.name)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                if let onDone {
                    ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone).accessibilityIdentifier("tone.done") }
                }
            }
            .onAppear { model.activate(arrangement, songId: songId == model.activeSongId ? songId : nil) }
            .sheet(isPresented: $addingLayer) {
                PatchPicker { patch in
                    mutate { $0.layers.append(Layer(patchId: patch.id, volume: 0.6)) }
                }
            }
            .sheet(item: Binding(get: { pickingPatchForLayer.map(IdentifiedID.init) }, set: { pickingPatchForLayer = $0?.id })) { item in
                PatchPicker { patch in
                    mutate { a in
                        if let i = a.layers.firstIndex(where: { $0.id == item.id }) { a.layers[i].patchId = patch.id }
                    }
                }
            }
        } else {
            ContentUnavailableView("Tone not found", systemImage: "questionmark")
        }
    }

    private var maxLayers: Int { model.engineKind == .tonePilot ? ToneEngine.liveSlotCount : SoundEngine.maxLayers }

    private func duplicate(_ a: Arrangement) {
        let copy = a.duplicated()
        model.updateArrangement(copy, inSong: songId)
    }

    private func masterSection(_ arrangement: Arrangement) -> some View {
        let m = Binding(get: { arrangement.masterEffects }, set: { v in mutate { $0.master = v } })
        return Section {
            HStack { Text("Reverb").frame(width: 80, alignment: .leading); Slider(value: m.reverbLevel, in: 0...1.5) }
            HStack { Text("Room size").frame(width: 80, alignment: .leading); Slider(value: m.reverbSize, in: 0...1) }
            HStack { Text("Chorus").frame(width: 80, alignment: .leading); Slider(value: m.chorusLevel, in: 0...1.5) }
            HStack { Text("Delay").frame(width: 80, alignment: .leading); Slider(value: m.delayLevel, in: 0...1.5) }
            HStack { Text("Delay \(Int(m.wrappedValue.delayTime * 1000)) ms").frame(width: 110, alignment: .leading); Slider(value: m.delayTime, in: 0.05...1.2) }
            HStack { Text("Feedback").frame(width: 80, alignment: .leading); Slider(value: m.delayFeedback, in: 0...0.85) }
            HStack { Text("EQ low").frame(width: 80, alignment: .leading); Slider(value: m.eq.lowDB, in: -12...12, step: 0.5) }
            HStack { Text("EQ mid").frame(width: 80, alignment: .leading); Slider(value: m.eq.midDB, in: -12...12, step: 0.5) }
            HStack { Text("EQ high").frame(width: 80, alignment: .leading); Slider(value: m.eq.highDB, in: -12...12, step: 0.5) }
        } header: { Text("Master effects") } footer: {
            Text("Layers send to these shared effects by their own reverb/chorus/delay amounts. A limiter keeps the output from clipping into the Casio's AUDIO IN.")
        }
    }

    private func mutate(_ change: (inout Arrangement) -> Void) {
        guard var a = arrangement, a.origin != .aiOriginal else { return }
        change(&a)
        model.updateArrangement(a, inSong: songId)
    }

    private func binding<T>(_ path: WritableKeyPath<Arrangement, T>) -> Binding<T> {
        Binding(get: { arrangement![keyPath: path] }, set: { v in mutate { $0[keyPath: path] = v } })
    }

    private func layerBinding(_ id: UUID) -> Binding<Layer> {
        Binding(
            get: { arrangement?.layers.first { $0.id == id } ?? Layer(patchId: UUID()) },
            set: { new in mutate { a in if let i = a.layers.firstIndex(where: { $0.id == id }) { a.layers[i] = new } } }
        )
    }
}

struct IdentifiedID: Identifiable { let id: UUID }

struct LayerEditor: View {
    @Binding var layer: Layer
    let patch: InstrumentPatch?
    let color: Color
    let expanded: Bool
    let onToggle: () -> Void
    let onChangePatch: () -> Void
    /// TonePilot engine: envelope, filter, EQ, chorus and expression are available.
    var fullControls = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(color).frame(width: 10, height: 10)
                Button(action: onToggle) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(patch?.name ?? "Missing patch").font(.headline)
                        HStack(spacing: 6) {
                            if let patch { SourceTypeBadge(type: patch.sourceType) }
                            Text(summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("layer.header")
                Spacer()
                Toggle("M", isOn: $layer.muted).toggleStyle(.button).controlSize(.small).tint(Theme.warn)
                    .accessibilityLabel("Mute")
                Toggle("S", isOn: $layer.solo).toggleStyle(.button).controlSize(.small).tint(.yellow)
                    .accessibilityLabel("Solo")
            }
            HStack {
                Image(systemName: "speaker.fill").font(.caption)
                Slider(value: $layer.volume, in: 0...1)
            }
            if expanded { details }
        }
        .opacity(layer.enabled ? 1 : 0.5)
    }

    private var summary: String {
        var parts: [String] = []
        if layer.octave != 0 { parts.append("oct \(layer.octave > 0 ? "+" : "")\(layer.octave)") }
        if layer.transpose != 0 { parts.append("\(layer.transpose > 0 ? "+" : "")\(layer.transpose) st") }
        if layer.keyRange != .full { parts.append("\(NoteName.name(for: Int(layer.keyRange.low)))–\(NoteName.name(for: Int(layer.keyRange.high)))") }
        if layer.velocityRange != .full { parts.append("vel \(layer.velocityRange.low)–\(layer.velocityRange.high)") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var details: some View {
        Button("Change sound…", action: onChangePatch)
        Toggle("Enabled", isOn: $layer.enabled)
        HStack { Text("Pan"); Slider(value: $layer.pan, in: -1...1) }
        Stepper("Octave \(layer.octave > 0 ? "+" : "")\(layer.octave)", value: $layer.octave, in: -3...3)
        Stepper("Transpose \(layer.transpose > 0 ? "+" : "")\(layer.transpose) semitones", value: $layer.transpose, in: -12...12)
        HStack {
            Text("Fine tune \(Int(layer.fineTuneCents)) ct")
            Slider(value: $layer.fineTuneCents, in: -100...100, step: 1)
        }
        Stepper("Lowest key \(NoteName.name(for: Int(layer.keyRange.low)))",
                value: Binding(get: { Int(layer.keyRange.low) }, set: { layer.keyRange = KeyRange(low: UInt8($0), high: layer.keyRange.high) }),
                in: 0...Int(layer.keyRange.high))
        Stepper("Highest key \(NoteName.name(for: Int(layer.keyRange.high)))",
                value: Binding(get: { Int(layer.keyRange.high) }, set: { layer.keyRange = KeyRange(low: layer.keyRange.low, high: UInt8($0)) }),
                in: Int(layer.keyRange.low)...127)
        Stepper("Softest velocity \(layer.velocityRange.low)",
                value: Binding(get: { Int(layer.velocityRange.low) }, set: { layer.velocityRange = VelocityRange(low: UInt8($0), high: layer.velocityRange.high) }),
                in: 1...Int(layer.velocityRange.high), step: 5)
        Stepper("Hardest velocity \(layer.velocityRange.high)",
                value: Binding(get: { Int(layer.velocityRange.high) }, set: { layer.velocityRange = VelocityRange(low: layer.velocityRange.low, high: UInt8($0)) }),
                in: Int(layer.velocityRange.low)...127, step: 5)
        Picker("MIDI channel", selection: $layer.midiChannel) {
            Text("Any").tag(UInt8?.none)
            ForEach(1...16, id: \.self) { Text("\($0)").tag(UInt8?.some(UInt8($0))) }
        }
        Picker("Role", selection: $layer.role) {
            Text("None").tag(MusicalRole?.none)
            ForEach(MusicalRole.allCases, id: \.self) { Text($0.displayName).tag(MusicalRole?.some($0)) }
        }
        let effects = Binding(get: { layer.effectsOverride ?? patch?.effects ?? EffectSettings() },
                              set: { layer.effectsOverride = $0 })
        DisclosureGroup("Effects & EQ") {
            HStack { Text("Reverb"); Slider(value: effects.reverbMix, in: 0...100) }
            HStack { Text("Chorus"); Slider(value: effects.chorusMix, in: 0...100) }.disabled(!fullControls)
            HStack { Text("Delay"); Slider(value: effects.delayMix, in: 0...100) }
            // Warm saturation for powerful leads, brass and synths (0 = clean).
            HStack { Text("Drive"); Slider(value: effects.drive, in: 0...100).accessibilityIdentifier("layer.drive") }
            if !fullControls, effects.wrappedValue.delayMix > 0 {
                HStack { Text("Delay time"); Slider(value: effects.delayTime, in: 0.05...1.5) }
                HStack { Text("Feedback"); Slider(value: effects.delayFeedback, in: 0...90) }
            }
            if fullControls {
                eqSlider("Low", effects.eq.lowDB)
                eqSlider("Mid", effects.eq.midDB)
                eqSlider("High", effects.eq.highDB)
            }
        }
        if fullControls {
            DisclosureGroup("Envelope (attack · decay · sustain · release)") {
                Toggle(patch?.usesOwnEnvelope == true ? "Override the patch envelope" : "Override the SoundFont's envelope",
                       isOn: Binding(get: { layer.envelopeOverride != nil },
                                     set: { layer.envelopeOverride = $0 ? (patch?.envelope ?? Envelope()) : nil }))
                if layer.envelopeOverride != nil {
                    let env = Binding(get: { layer.envelopeOverride ?? Envelope() }, set: { layer.envelopeOverride = $0 })
                    timeSlider("Attack", env.attack, 0.001...3)
                    timeSlider("Decay", env.decay, 0.01...5)
                    HStack { Text("Sustain \(Int(env.wrappedValue.sustain * 100))%"); Slider(value: env.sustain, in: 0...1) }
                    timeSlider("Release", env.release, 0.01...6)
                }
            }
            DisclosureGroup("Filter") {
                let filter = Binding(get: { layer.filterOverride ?? patch?.filter ?? FilterSettings() }, set: { layer.filterOverride = $0 })
                Toggle("Low-pass filter", isOn: filter.enabled)
                if filter.wrappedValue.enabled {
                    HStack {
                        Text("Cutoff \(Int(filter.wrappedValue.cutoff)) Hz").frame(width: 130, alignment: .leading)
                        Slider(value: Binding(get: { log10(filter.wrappedValue.cutoff) }, set: { filter.wrappedValue.cutoff = pow(10, $0) }), in: log10(80)...log10(18_000))
                    }
                    HStack { Text("Resonance \(Int(filter.wrappedValue.resonance)) dB").frame(width: 130, alignment: .leading); Slider(value: filter.resonance, in: 0...18) }
                }
            }
            DisclosureGroup("Expression (mono · glide · vibrato · bend)") {
                let ex = Binding(get: { layer.expressionOverride ?? patch?.expression ?? .poly }, set: { layer.expressionOverride = $0 })
                Toggle("Mono / legato (one note at a time)", isOn: ex.mono)
                if ex.wrappedValue.mono { timeSlider("Glide", ex.glideTime, 0...0.5) }
                HStack { Text("Vibrato \(Int(ex.wrappedValue.vibratoDepth)) ct").frame(width: 110, alignment: .leading); Slider(value: ex.vibratoDepth, in: 0...60) }
                if ex.wrappedValue.vibratoDepth > 0 {
                    HStack { Text("Rate \(ex.wrappedValue.vibratoRate, specifier: "%.1f") Hz").frame(width: 110, alignment: .leading); Slider(value: ex.vibratoRate, in: 2...9) }
                    timeSlider("Vibrato delay", ex.vibratoDelay, 0...1.5)
                }
                Stepper("Pitch-bend range ±\(Int(ex.wrappedValue.bendRange)) semitones", value: ex.bendRange, in: 1...12)
                HStack { Text("Velocity response"); Slider(value: ex.velocitySensitivity, in: 0...1) }
            }
        } else {
            Text("Envelope, filter, EQ, chorus and expression need the TonePilot engine (Settings › Sound engine).")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func eqSlider(_ name: String, _ value: Binding<Double>) -> some View {
        HStack { Text("\(name) \(value.wrappedValue >= 0 ? "+" : "")\(value.wrappedValue, specifier: "%.0f") dB").frame(width: 110, alignment: .leading); Slider(value: value, in: -12...12, step: 0.5) }
    }

    private func timeSlider(_ name: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack {
            Text("\(name) \(value.wrappedValue < 1 ? "\(Int(value.wrappedValue * 1000)) ms" : String(format: "%.1f s", value.wrappedValue))")
                .frame(width: 130, alignment: .leading)
            Slider(value: value, in: range)
        }
    }
}

struct PatchPicker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let onPick: (InstrumentPatch) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(InstrumentFamily.allCases, id: \.self) { family in
                    let patches = model.library.patches.filter {
                        $0.family == family && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))
                    }
                    if !patches.isEmpty {
                        Section(family.displayName) {
                            ForEach(patches) { p in
                                Button { onPick(p); dismiss() } label: {
                                    HStack {
                                        Text(p.name)
                                        Spacer()
                                        SourceTypeBadge(type: p.sourceType)
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle("Choose sound")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
