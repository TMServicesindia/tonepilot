import SwiftUI
import TonePilotCore
import UniformTypeIdentifiers

/// Builds a playable instrument from authorised samples (your recordings, a licensed pack, or an
/// isolated stem you're allowed to use). Each sample gets a root note and key range; several
/// samples across the keyboard give a far more realistic instrument than one stretched sample.
struct SamplePatchCreatorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    struct Row: Identifiable {
        let id = UUID()
        var url: URL
        var root: Int = 60
        var low: Int = 48
        var high: Int = 72
        var trimStart: Double = 0
        var trimEnd: Double = 0
        var duration: Double = 0
        var loop = false
        var loopStart: Double = 0.2
        var loopEnd: Double = 0.8
    }

    @State private var name = "My Instrument"
    @State private var family: InstrumentFamily = .other
    @State private var rows: [Row] = []
    @State private var envelope = Envelope(attack: 0.005, decay: 0.3, sustain: 0.9, release: 0.4)
    @State private var licenseName = ""
    @State private var confirmed = false
    @State private var picking = false
    @State private var result: String?
    @State private var experimentalStem = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                Picker("Family", selection: $family) {
                    ForEach(InstrumentFamily.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Built from an AI-separated stem (experimental)", isOn: $experimentalStem)
            }
            Section {
                ForEach($rows) { $row in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.url.lastPathComponent).font(.headline).lineLimit(1)
                        Stepper("Recorded pitch (root): \(NoteName.name(for: row.root))", value: $row.root, in: 24...108)
                        Stepper("Lowest key: \(NoteName.name(for: row.low))", value: $row.low, in: 0...row.high)
                        Stepper("Highest key: \(NoteName.name(for: row.high))", value: $row.high, in: row.low...127)
                        if row.duration > 0 {
                            HStack { Text("Start \(row.trimStart, specifier: "%.2f") s").frame(width: 110, alignment: .leading); Slider(value: $row.trimStart, in: 0...max(0.01, row.trimEnd - 0.05)) }
                            HStack { Text("End \(row.trimEnd, specifier: "%.2f") s").frame(width: 110, alignment: .leading); Slider(value: $row.trimEnd, in: min(row.duration, row.trimStart + 0.05)...row.duration) }
                            Toggle("Loop while held (sustained sounds)", isOn: $row.loop)
                            if row.loop {
                                HStack { Text("Loop from \(row.loopStart, specifier: "%.2f")").frame(width: 110, alignment: .leading); Slider(value: $row.loopStart, in: row.trimStart...max(row.trimStart + 0.01, row.loopEnd - 0.02)) }
                                HStack { Text("Loop to \(row.loopEnd, specifier: "%.2f")").frame(width: 110, alignment: .leading); Slider(value: $row.loopEnd, in: min(row.trimEnd, row.loopStart + 0.02)...row.trimEnd) }
                            }
                        }
                        if max(abs(row.low - row.root), abs(row.high - row.root)) > 7 {
                            Text("Covers more than ±7 semitones from its recorded pitch — far keys will sound pitch-shifted.").font(.caption2).foregroundStyle(Theme.warn)
                        }
                    }
                }
                .onDelete { rows.remove(atOffsets: $0) }
                Button { picking = true } label: { Label("Add sample files…", systemImage: "plus") }
            } header: { Text("Samples") } footer: {
                Text("For a realistic instrument, record or import notes every 4–7 semitones across the range and map each to the keys around it.")
            }
            Section("Envelope") {
                HStack { Text("Attack").frame(width: 70, alignment: .leading); Slider(value: $envelope.attack, in: 0.001...2) }
                HStack { Text("Decay").frame(width: 70, alignment: .leading); Slider(value: $envelope.decay, in: 0.01...4) }
                HStack { Text("Sustain").frame(width: 70, alignment: .leading); Slider(value: $envelope.sustain, in: 0...1) }
                HStack { Text("Release").frame(width: 70, alignment: .leading); Slider(value: $envelope.release, in: 0.01...5) }
            }
            Section {
                TextField("Source / licence (e.g. \"My own recording\")", text: $licenseName)
                Toggle("I recorded these or have the right to use them", isOn: $confirmed)
                Button("Create instrument") { create() }
                    .disabled(rows.isEmpty || !confirmed || name.isEmpty)
                if let result { Text(result).font(.footnote) }
            }
        }
        .navigationTitle("Sample instrument")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio, .wav, .aiff, .mp3, .mpeg4Audio], allowsMultipleSelection: true) { r in
            guard let urls = try? r.get() else { return }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                let d = AudioFileDecoder.duration(of: url) ?? 0
                if scoped { url.stopAccessingSecurityScopedResource() }
                var row = Row(url: url)
                row.duration = d
                row.trimEnd = d
                row.loopStart = d * 0.3
                row.loopEnd = d * 0.8
                // Spread new samples up the keyboard by default.
                let i = rows.count
                row.root = 48 + i * 7
                row.low = row.root - 3
                row.high = row.root + 3
                rows.append(row)
            }
        }
    }

    private func create() {
        let inputs = rows.map { r in
            AppModel.SampleInput(url: r.url, rootNote: UInt8(r.root), keyRange: KeyRange(low: UInt8(r.low), high: UInt8(r.high)),
                                 trimStart: r.trimStart, trimEnd: r.trimEnd > 0 ? r.trimEnd : nil,
                                 loop: r.loop ? r.loopStart...r.loopEnd : nil)
        }
        do {
            var (patch, warning) = try model.createSamplePatch(name: name, family: family, samples: inputs, envelope: envelope,
                                                                license: LicenseInfo(name: licenseName.isEmpty ? "User supplied" : licenseName, redistributable: false))
            if experimentalStem {
                patch.sourceType = .experimentalExtraction
                patch.notes = "Built from an AI-separated stem: expect artifacts and bleed."
                model.library.upsert(patch)
                model.save()
            }
            result = "Created “\(patch.name)”. Add it as a layer in Tone Studio." + (warning.map { "\n⚠︎ " + $0 } ?? "")
        } catch {
            result = "Couldn't create the instrument: \(error.localizedDescription)"
        }
    }
}
