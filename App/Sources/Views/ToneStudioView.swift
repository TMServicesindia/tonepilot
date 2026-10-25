import SwiftUI
import TonePilotCore

/// Tone Studio tab: every saved composite tone, global or per song.
struct ToneStudioHomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: (songId: UUID?, arrangementId: UUID)?
    @State private var showEditor = false

    var body: some View {
        List {
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
                    ForEach(song.arrangements) { a in row(a, songId: song.id) }
                }
            }
        }
        .navigationTitle("Tone Studio")
        .toolbar { ToolbarItem(placement: .topBarLeading) { ConnectionStatus(midi: model.midi) } }
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
                    Text(a.name).font(.headline)
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
    @State private var expandedLayer: UUID?
    @State private var pickingPatchForLayer: UUID?
    @State private var addingLayer = false

    private static let layerColors: [Color] = [.orange, .teal, .purple, .pink, .yellow, .mint]

    private var arrangement: Arrangement? {
        if let songId { return model.song(songId)?.arrangements.first { $0.id == arrangementId } }
        return model.library.globalArrangements.first { $0.id == arrangementId }
    }

    var body: some View {
        if let arrangement {
            Form {
                Section {
                    TextField("Tone name", text: binding(\.name))
                    HStack {
                        Text("Master")
                        Slider(value: binding(\.masterGain), in: 0...1)
                    }
                    OutputMeter()
                    Button {
                        model.activate(arrangement, songId: songId)
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
                                    onChangePatch: { pickingPatchForLayer = layer.id })
                    }
                    .onDelete { offsets in mutate { $0.layers.remove(atOffsets: offsets) } }
                    .onMove { from, to in mutate { $0.layers.move(fromOffsets: from, toOffset: to) } }
                    if arrangement.layers.count < SoundEngine.maxLayers {
                        Button { addingLayer = true } label: { Label("Add layer", systemImage: "plus") }
                    } else {
                        Text("Maximum \(SoundEngine.maxLayers) layers on this device.").font(.caption).foregroundStyle(.secondary)
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

                Section { AuditionStrip() }
            }
            .navigationTitle(arrangement.name)
            .toolbar { EditButton() }
            .onAppear { model.activate(arrangement, songId: songId) }
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

    private func mutate(_ change: (inout Arrangement) -> Void) {
        guard var a = arrangement else { return }
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
        let effects = Binding(get: { layer.effectsOverride ?? patch?.effects ?? EffectSettings() },
                              set: { layer.effectsOverride = $0 })
        HStack { Text("Reverb"); Slider(value: effects.reverbMix, in: 0...100) }
        HStack { Text("Delay"); Slider(value: effects.delayMix, in: 0...100) }
        if effects.wrappedValue.delayMix > 0 {
            HStack { Text("Delay time"); Slider(value: effects.delayTime, in: 0.05...1.5) }
            HStack { Text("Feedback"); Slider(value: effects.delayFeedback, in: 0...90) }
        }
        Text("Attack/release come from the SoundFont preset in this version; per-layer envelope editing arrives with the sample engine (Milestone 3).")
            .font(.caption2).foregroundStyle(.secondary)
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
