import SwiftUI
import TonePilotCore

/// Blind A/B listening test (sound-engine phase 1): two tones play the song's own melody as
/// "Sound X" and "Sound Y" in random order; you pick the one that sounds more like the song, then
/// see which was which. Results are kept on this iPhone (they decide whether real-instrument
/// sounds become defaults; nothing is sent anywhere).
struct BlindCompareView: View {
    @EnvironmentObject var model: AppModel
    let songId: UUID
    let onDone: () -> Void

    @State private var first: UUID?
    @State private var second: UUID?
    @State private var order: [UUID] = []          // [X, Y] once the test starts
    @State private var choice: Int?                // 0 = X, 1 = Y
    @State private var playing: Int?
    @State private var results: [BlindCompareResult] = BlindCompareResult.load()

    private var song: Song? { model.song(songId) }

    /// Tones you can compare: the song's own tones, then installed real-instrument tones, then the library.
    private var candidates: [Arrangement] {
        var list = song?.arrangements.filter { $0.origin != .aiOriginal } ?? []
        let real = model.library.patches.filter { $0.tags?.contains("sound-pack") == true }
        list += real.map(Arrangement.single)
        return list
    }

    private func name(_ id: UUID?) -> String { candidates.first { $0.id == id }?.name ?? "—" }

    var body: some View {
        Form {
            if order.isEmpty {
                Section {
                    Picker("First sound", selection: $first) {
                        Text("Choose").tag(UUID?.none)
                        ForEach(candidates) { Text($0.name).tag(Optional($0.id)) }
                    }.accessibilityIdentifier("compare.first")
                    Picker("Second sound", selection: $second) {
                        Text("Choose").tag(UUID?.none)
                        ForEach(candidates) { Text($0.name).tag(Optional($0.id)) }
                    }.accessibilityIdentifier("compare.second")
                    Button("Start blind test") {
                        guard let a = first, let b = second, a != b else { return }
                        order = Bool.random() ? [a, b] : [b, a]
                        choice = nil
                    }
                    .disabled(first == nil || second == nil || first == second)
                    .accessibilityIdentifier("compare.start")
                } footer: {
                    Text("Pick today's tone and a real-instrument tone (download them in Settings › Real instrument sounds). The test hides which is which.")
                }
            } else {
                Section {
                    ForEach(0..<2, id: \.self) { i in
                        HStack {
                            Button { play(i) } label: {
                                Label(i == 0 ? "Play Sound X" : "Play Sound Y", systemImage: playing == i ? "speaker.wave.2.fill" : "play.fill")
                            }
                            .accessibilityIdentifier(i == 0 ? "compare.playX" : "compare.playY")
                            Spacer()
                            Button(choice == i ? "Chosen" : "This one") { decide(i) }
                                .buttonStyle(.bordered).disabled(choice != nil)
                                .accessibilityIdentifier(i == 0 ? "compare.chooseX" : "compare.chooseY")
                        }
                    }
                } header: {
                    Text("Which sounds more like the song?")
                } footer: {
                    Text("Each plays the song's melody for up to 10 seconds. Listen to both, as often as you like.")
                }
                if let c = choice {
                    Section("Result") {
                        Text("You chose \(name(order[c])).").font(DS.Text.label)
                        Text("Sound X was \(name(order[0])); Sound Y was \(name(order[1])).").font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                        Button("Another round") { order = Bool.random() ? order : order.reversed(); choice = nil }
                        Button("New pair") { order = []; choice = nil }
                    }
                }
            }
            if !results.isEmpty {
                Section("Your results (\(results.count))") {
                    ForEach(results.suffix(6).reversed()) { r in
                        Text("\(r.songTitle): chose \(r.winnerName) over \(r.loserName)").font(DS.Text.metadata)
                    }
                }
            }
        }
        .navigationTitle("Blind comparison")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { stop(); onDone() }.accessibilityIdentifier("compare.done") } }
        .onAppear {
            if first == nil { first = song.flatMap { model.mainTone(of: $0)?.id } }
        }
        .onDisappear { stop() }
    }

    /// The song's melody (≤ 10 s from the main section, else the start) on tone `order[i]`.
    private func play(_ i: Int) {
        guard let tone = candidates.first(where: { $0.id == order[i] }), let song else { return }
        stop()
        playing = i
        model.previewTone(tone)
        let section = song.orderedSections.first { $0.type == .chorus } ?? song.orderedSections.first
        let from = section?.startTime ?? 0
        let notes = (song.melody?.notes(in: from, from + 30) ?? []).filter { $0.start < from + 10 }
        let t0 = notes.first?.start ?? from
        let token = UUID()
        playToken = token
        for n in notes where (24...108).contains(n.midi) {
            let note = UInt8(n.midi)
            DispatchQueue.main.asyncAfter(deadline: .now() + (n.start - t0)) { if playToken == token { model.audition(note: note, on: true) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + (n.end - t0)) { model.audition(note: note, on: false) }
        }
        let end = (notes.last?.end ?? t0) - t0 + 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + end) { if playToken == token { playing = nil } }
    }

    @State private var playToken = UUID()

    private func stop() {
        playToken = UUID()
        playing = nil
        for n in UInt8(24)...UInt8(108) { model.audition(note: n, on: false) }
        model.endTonePreview()
    }

    private func decide(_ i: Int) {
        stop()
        choice = i
        let r = BlindCompareResult(id: UUID(), date: Date(), songTitle: song?.title ?? "", winnerName: name(order[i]), loserName: name(order[1 - i]))
        results.append(r)
        BlindCompareResult.save(results)
    }
}

/// One blind-test answer (kept in UserDefaults on this iPhone).
struct BlindCompareResult: Codable, Identifiable {
    let id: UUID
    let date: Date
    let songTitle: String
    let winnerName: String
    let loserName: String

    static let key = "blindCompareResults"
    static func load() -> [BlindCompareResult] {
        (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([BlindCompareResult].self, from: $0) } ?? []
    }
    static func save(_ list: [BlindCompareResult]) {
        if let d = try? JSONEncoder().encode(Array(list.suffix(200))) { UserDefaults.standard.set(d, forKey: key) }
    }
}
