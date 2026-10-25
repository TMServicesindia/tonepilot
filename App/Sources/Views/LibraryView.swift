import SwiftUI
import TonePilotCore
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var showImport = false
    @State private var showListen = false
    @State private var pickMP3 = false
    @State private var openedSong: UUID?
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
            if let error = model.importError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.bad).font(.footnote)
                    Button("Try again") { model.importError = nil; pickMP3 = true }
                }
            }
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
                        Text(query.isEmpty ? "Play a song from your streaming app and let TonePilot listen, or import an audio file you own. TonePilot builds tones for every section automatically."
                                           : "Try a title, film, composer, language or tag.")
                    } actions: {
                        if query.isEmpty {
                            Button("Listen to a song") { showListen = true }.buttonStyle(.borderedProminent)
                            Button("Import MP3") { pickMP3 = true }
                        }
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
        .navigationDestination(item: $openedSong) { SongDetailView(songId: $0) }
        .fileImporter(isPresented: $pickMP3, allowedContentTypes: [.mp3, .mpeg4Audio, .wav, .aiff, .audio]) { result in
            if case .success(let url) = result, let id = model.importAndAnalyze(from: url) { openedSong = id }
        }
        .searchable(text: $query, prompt: "Title, film, composer, language, tag")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { ConnectionStatus(midi: model.midi) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showListen = true } label: { Label("Listen to a song (streaming app)", systemImage: "ear") }
                    Button { pickMP3 = true } label: { Label("Import MP3 / audio file", systemImage: "square.and.arrow.down") }
                    Button { showImport = true } label: { Label("Save a YouTube link", systemImage: "link") }
                    Button { showNewPlaylist = true } label: { Label("New playlist", systemImage: "text.badge.plus") }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showImport) { ImportSongView().environmentObject(model) }
        .sheet(isPresented: $showListen) { ListenModeView().environmentObject(model) }
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
            Image(systemName: song.sourceType == .youtubeLink ? "link" : song.sourceType == .listened ? "ear" : "waveform")
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
                        Button { pickFile = true } label: { Label("Choose MP3 / audio file…", systemImage: "folder") }
                    } footer: {
                        Text("MP3, M4A, WAV and AIFF. Analysis starts as soon as the file is added; title and artist come from the file's tags or its name.")
                    }
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
        guard let id = model.importAndAnalyze(from: url) else { error = model.importError; return }
        // Details typed in the form (optional) override the file's tags.
        if var song = model.song(id) {
            if !title.isEmpty { song.title = title }
            applyDetails(&song)
            model.update(song)
        }
        dismiss()
    }

    private func saveLink() {
        var song = Song(title: title, sourceType: .youtubeLink, sourceReference: link, analysisStatus: .unavailable)
        song.arrangements = [.starterFilmStack(name: "Main tone")]
        applyDetails(&song)
        model.update(song)
        dismiss()
    }
}
