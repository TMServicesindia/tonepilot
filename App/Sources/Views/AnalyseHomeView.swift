import SwiftUI
import TonePilotCore

/// Analyse tab: songs and their analysis state.
struct AnalyseHomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var showImport = false
    @State private var showListen = false

    var body: some View {
        List {
            Section {
                Button { showListen = true } label: { Label("Listen to a song from your streaming app", systemImage: "ear") }
                Button { showImport = true } label: { Label("Import an audio file you own", systemImage: "square.and.arrow.down") }
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
    }
}
