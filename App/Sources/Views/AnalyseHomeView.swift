import SwiftUI
import TonePilotCore
import UniformTypeIdentifiers

/// Analyse tab: songs and their analysis state.
struct AnalyseHomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var showImport = false
    @State private var showListen = false
    @State private var pickMP3 = false

    var body: some View {
        List {
            Section {
                Button { showListen = true } label: { Label("Listen to a song from your streaming app", systemImage: "ear") }
                Button { pickMP3 = true } label: { Label("Import MP3 / audio file", systemImage: "square.and.arrow.down") }
            } footer: {
                Text("Analysis runs on this iPhone: tempo & beats, key, chords, section boundaries and repeated parts, plus tone suggestions.")
            }
            Section("Songs") {
                ForEach(model.library.songs.filter { [.importedFile, .listened].contains($0.sourceType) }) { song in
                    NavigationLink(value: song.id) {
                        HStack {
                            Text(song.title)
                            Spacer()
                            switch song.analysisStatus {
                            case .running: ProgressView(value: model.analysisProgress[song.id] ?? 0).frame(width: 60)
                            case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.bad)
                            default: Text("Not analysed").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Analyse")
        .navigationDestination(for: UUID.self) { SongDetailView(songId: $0) }
        .sheet(isPresented: $showImport) { ImportSongView().environmentObject(model) }
        .sheet(isPresented: $showListen) { ListenModeView().environmentObject(model) }
        .fileImporter(isPresented: $pickMP3, allowedContentTypes: [.mp3, .mpeg4Audio, .wav, .aiff, .audio]) { result in
            if case .success(let url) = result { model.importAndAnalyze(from: url) }
        }
    }
}
