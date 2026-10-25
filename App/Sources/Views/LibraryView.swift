import SwiftUI
import TonePilotCore
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var showImport = false
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var filterPlaylist: UUID?

    private var songs: [Song] {
        var list = model.library.searchSongs(query)
        if let pid = filterPlaylist, let playlist = model.library.playlists.first(where: { $0.id == pid }) {
            let order = Dictionary(uniqueKeysWithValues: playlist.songIds.enumerated().map { ($1, $0) })
            list = list.filter { order[$0.id] != nil }.sorted { order[$0.id]! < order[$1.id]! }
        } else {
            list.sort { ($0.isFavorite ? 0 : 1, $0.title.lowercased()) < ($1.isFavorite ? 0 : 1, $1.title.lowercased()) }
        }
        return list
    }

    var body: some View {
        List {
            if !model.library.playlists.isEmpty {
                Section("Playlists") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            chip("All songs", selected: filterPlaylist == nil) { filterPlaylist = nil }
                            ForEach(model.library.playlists) { p in
                                chip("\(p.name) (\(p.songIds.count))", selected: filterPlaylist == p.id) { filterPlaylist = p.id }
                                    .contextMenu {
                                        Button("Delete playlist", role: .destructive) {
                                            model.library.playlists.removeAll { $0.id == p.id }
                                            if filterPlaylist == p.id { filterPlaylist = nil }
                                            model.save()
                                        }
                                    }
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                if songs.isEmpty {
                    ContentUnavailableView {
                        Label(query.isEmpty ? "No songs yet" : "No matches", systemImage: "music.note")
                    } description: {
                        Text(query.isEmpty ? "Import an MP3 you own to analyse it and build tones for its intro, interludes and chorus."
                                           : "Try a title, film, composer, language or tag.")
                    } actions: {
                        if query.isEmpty { Button("Import a song") { showImport = true }.buttonStyle(.borderedProminent) }
                    }
                }
                ForEach(songs) { song in
                    NavigationLink(value: song.id) { SongRow(song: song) }
                        .swipeActions {
                            Button(role: .destructive) { model.deleteSong(song.id) } label: { Label("Delete", systemImage: "trash") }
                            Button {
                                var s = song; s.isFavorite.toggle(); model.update(s)
                            } label: { Label("Favourite", systemImage: "star") }.tint(.yellow)
                        }
                        .contextMenu {
                            Menu("Add to playlist") {
                                ForEach(model.library.playlists) { p in
                                    Button(p.name) {
                                        if let i = model.library.playlists.firstIndex(where: { $0.id == p.id }),
                                           !model.library.playlists[i].songIds.contains(song.id) {
                                            model.library.playlists[i].songIds.append(song.id)
                                            model.save()
                                        }
                                    }
                                }
                            }
                        }
                }
            }
        }
        .navigationTitle("Library")
        .navigationDestination(for: UUID.self) { SongDetailView(songId: $0) }
        .searchable(text: $query, prompt: "Title, film, composer, language, tag")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { ConnectionStatus(midi: model.midi) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showImport = true } label: { Label("Import song", systemImage: "square.and.arrow.down") }
                    Button { showNewPlaylist = true } label: { Label("New playlist", systemImage: "text.badge.plus") }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showImport) { ImportSongView().environmentObject(model) }
        .alert("New playlist", isPresented: $showNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") {
                let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { model.library.playlists.append(Playlist(name: name)); model.save() }
                newPlaylistName = ""
            }
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Theme.accent : Theme.panelRaised, in: Capsule())
                .foregroundStyle(selected ? .black : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct SongRow: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: song.sourceType == .youtubeLink ? "link" : "waveform")
                .frame(width: 36, height: 36)
                .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(song.title).font(.headline).lineLimit(1)
                    if song.isFavorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                }
                Text([song.film, song.composer, song.language].compactMap { $0 }.joined(separator: " · ").ifEmpty("No details"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let bpm = song.bpm { Text("\(Int(bpm.value.rounded())) BPM").font(.caption.monospacedDigit()) }
                if let key = song.key { Text(key.value.displayName).font(.caption2).foregroundStyle(.secondary) }
                if song.analysisStatus == .running { ProgressView().controlSize(.mini) }
            }
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

/// Import an audio file the user owns or is authorised to use, or save a YouTube link as reference only.
struct ImportSongView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var title = ""
    @State private var film = ""
    @State private var composer = ""
    @State private var language = ""
    @State private var link = ""
    @State private var rightsConfirmed = false
    @State private var analyseNow = true
    @State private var pickFile = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Source", selection: $mode) {
                    Text("Audio file").tag(0)
                    Text("YouTube link").tag(1)
                }
                .pickerStyle(.segmented)

                Section("Details") {
                    TextField("Title (optional for files)", text: $title)
                    TextField("Film / album", text: $film)
                    TextField("Composer", text: $composer)
                    TextField("Language", text: $language)
                }

                if mode == 0 {
                    Section {
                        Toggle("I own this audio or am authorised to process it", isOn: $rightsConfirmed)
                        Toggle("Analyse after import", isOn: $analyseNow)
                    } footer: {
                        Text("MP3, M4A, WAV and AIFF are supported. Audio is copied into TonePilot and analysed on this iPhone — nothing is uploaded.")
                    }
                    Button { pickFile = true } label: {
                        Label("Choose audio file…", systemImage: "folder")
                    }
                    .disabled(!rightsConfirmed)
                } else {
                    Section {
                        TextField("https://www.youtube.com/watch?v=…", text: $link)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } footer: {
                        Text("TonePilot stores the link for reference and opens it in YouTube. It does not download or analyse YouTube audio — YouTube's terms don't allow that. To analyse the song, import an audio file you own.")
                    }
                    Button("Save link") { saveLink() }
                        .disabled(URL(string: link)?.host?.contains("youtu") != true || title.isEmpty)
                }

                if let error { Text(error).foregroundStyle(Theme.bad).font(.footnote) }
            }
            .navigationTitle("Add song")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .fileImporter(isPresented: $pickFile, allowedContentTypes: [.mp3, .mpeg4Audio, .wav, .aiff, .audio]) { result in
                switch result {
                case .success(let url): importFile(url)
                case .failure(let e): error = e.localizedDescription
                }
            }
        }
    }

    private func applyDetails(_ song: inout Song) {
        song.film = film.isEmpty ? nil : film
        song.composer = composer.isEmpty ? nil : composer
        song.language = language.isEmpty ? nil : language
    }

    private func importFile(_ url: URL) {
        do {
            var song = try model.importAudio(from: url, title: title, rightsConfirmed: rightsConfirmed)
            applyDetails(&song)
            model.update(song)
            if analyseNow { model.analyze(songId: song.id) }
            dismiss()
        } catch {
            self.error = "Import failed: \(error.localizedDescription)"
        }
    }

    private func saveLink() {
        var song = Song(title: title, sourceType: .youtubeLink, sourceReference: link, analysisStatus: .unavailable)
        song.arrangements = [.starterFilmStack(name: "Main tone")]
        applyDetails(&song)
        model.update(song)
        dismiss()
    }
}
