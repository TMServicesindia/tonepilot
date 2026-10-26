import SwiftUI
import TonePilotCore
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var showImport = false
    @State private var showListen = false
    @State private var pickMP3 = false
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

            if query.isEmpty, filterPlaylist == nil {
                Section { addSongCard }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                if let id = model.activeSongId, let song = model.song(id) {
                    Section("Continue") {
                        Button { model.openStudio(id) } label: {
                            HStack(spacing: 12) {
                                SongArtwork(title: song.title, size: 52)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title).font(.headline).lineLimit(1)
                                    Text("Back to Song Studio").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill").font(.title).foregroundStyle(Theme.accent)
                            }
                            .contentShape(Rectangle())
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            Section(songs.isEmpty ? "" : "Your songs") {
                if songs.isEmpty, !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                ForEach(songs) { song in
                    Button { model.openStudio(song.id) } label: {
                        SongRow(song: song, status: status(song)).contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                    .accessibilityHint("Opens the song in Song Studio")
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
        .navigationTitle("Songs")
        .fileImporter(isPresented: $pickMP3, allowedContentTypes: [.mp3, .mpeg4Audio, .wav, .aiff, .audio]) { result in
            if case .success(let url) = result, let id = model.importAndAnalyze(from: url) { model.openStudio(id) }
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
                } label: { Image(systemName: "plus.circle.fill").font(.title3).accessibilityLabel("Add") }
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

    /// The big "add a song" entry point (the main thing to do in an empty library).
    private var addSongCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.library.songs.isEmpty {
                Text("Play along with any song").font(.title2.weight(.bold))
                Text("Add a song you own. TonePilot finds the tempo, key, chords and sections, separates the vocals, drums, bass and music, and sets up a tone for every section.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button { pickMP3 = true } label: {
                    Label("Import song", systemImage: "square.and.arrow.down")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                Button { showListen = true } label: {
                    Label("Listen", systemImage: "ear")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.panel], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18))
    }

    /// What the song is ready for, in one pill.
    private func status(_ song: Song) -> SongRow.Status {
        if song.analysisStatus == .running {
            return .init(text: "Analysing \(Int(((model.analysisProgress[song.id] ?? 0) * 100).rounded()))%", color: Theme.warn, symbol: "waveform")
        }
        if let p = model.separationProgress[song.id] {
            return .init(text: "Separating \(Int((p * 100).rounded()))%", color: Theme.warn, symbol: "scissors")
        }
        if song.analysisStatus == .failed { return .init(text: "Needs attention", color: Theme.bad, symbol: "exclamationmark.triangle") }
        if song.sourceType == .youtubeLink { return .init(text: "Link only", color: .secondary, symbol: "link") }
        if !model.stemKinds(for: song).isEmpty { return .init(text: "Parts ready", color: Theme.good, symbol: "checkmark") }
        if song.analysisStatus == .completed { return .init(text: "Ready", color: Theme.good, symbol: "checkmark") }
        return .init(text: "Not analysed", color: .secondary, symbol: nil)
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
    struct Status { let text: String; let color: Color; let symbol: String? }
    let song: Song
    var status: Status?

    var body: some View {
        HStack(spacing: 12) {
            SongArtwork(title: song.title, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(song.title).font(.headline).lineLimit(1)
                    if song.isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                }
                Text([song.artist, song.film, song.composer].compactMap { $0 }.joined(separator: " · ").ifEmpty(details))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let status { StatusPill(text: status.text, color: status.color, symbol: status.symbol) }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var details: String {
        [song.bpm.map { "\(Int($0.value.rounded())) BPM" }, song.key?.value.displayName].compactMap { $0 }.joined(separator: " · ").ifEmpty("No details")
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
        model.openStudio(id)
        dismiss()
    }

    private func saveLink() {
        var song = Song(title: title, sourceType: .youtubeLink, sourceReference: link, analysisStatus: .unavailable)
        song.arrangements = [.starterFilmStack(name: "Main tone")]
        applyDetails(&song)
        model.update(song)
        model.openStudio(song.id)
        dismiss()
    }
}
