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
                if let id = model.activeSongId, let song = model.song(id) {
                    Section { ContinueCard(song: song) }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                Section { addSongActions }
                    .listRowInsets(EdgeInsets(top: DS.Space.xs, leading: 0, bottom: DS.Space.xs, trailing: 0)).listRowBackground(Color.clear)
                if model.library.songs.isEmpty {
                    Section { emptyLibrary }.listRowBackground(Color.clear)
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
                    .foregroundStyle(DS.Palette.textPrimary)
                    .listRowBackground(DS.Palette.surface)
                    .accessibilityIdentifier("songs.row.\(song.title)")
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
        .scrollContentBackground(.hidden)
        .dsCanvas()
        .navigationTitle("Songs")
        .fileImporter(isPresented: $pickMP3, allowedContentTypes: [.mp3, .mpeg4Audio, .wav, .aiff, .audio]) { result in
            if case .success(let url) = result, let id = model.importAndAnalyze(from: url) { model.openStudio(id) }
        }
        .searchable(text: $query, prompt: "Search songs")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { ConnectionStatus(midi: model.midi) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Import and Listen are the visible buttons above the list; only the extras live here.
                    Button { showImport = true } label: { Label("Save a YouTube link", systemImage: "link") }
                    Button { showNewPlaylist = true } label: { Label("New playlist", systemImage: "text.badge.plus") }
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("More") }
                .accessibilityIdentifier("songs.more")
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

    /// Import (primary) and Listen: the two ways to add a song.
    private var addSongActions: some View {
        HStack(spacing: DS.Space.s) {
            Button { pickMP3 = true } label: { Label("Import song", systemImage: "square.and.arrow.down") }
                .buttonStyle(.dsPrimary)
                .accessibilityIdentifier("songs.import")
            Button { showListen = true } label: { Label("Listen", systemImage: "ear") }
                .buttonStyle(.dsSecondary)
                .frame(maxWidth: 150)
                .accessibilityIdentifier("songs.listen")
        }
    }

    /// Empty library: one picture, one sentence, one action (the Import button above).
    private var emptyLibrary: some View {
        VStack(spacing: DS.Space.s) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array([0.4, 0.6, 0.9, 0.55, 0.75, 0.35].enumerated()), id: \.offset) { i, h in
                    RoundedRectangle(cornerRadius: 3).fill(i == 2 ? DS.Palette.accent : DS.Palette.group[i % 4].opacity(0.8))
                        .frame(width: 14, height: 70 * h)
                }
            }
            .frame(height: 80)
            Text("Import a song you own").font(DS.Text.section).foregroundStyle(DS.Palette.textPrimary)
            Text("MP3, M4A or WAV. TonePilot analyses it on this iPhone.")
                .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xl)
        .accessibilityElement(children: .combine)
    }

    /// What the song is ready for, in one chip.
    private func status(_ song: Song) -> SongRow.Status {
        if song.analysisStatus == .running {
            return .init(text: "Analysing \(Int(((model.analysisProgress[song.id] ?? 0) * 100).rounded()))%", tone: .accent, symbol: nil)
        }
        if let p = model.separationProgress[song.id] {
            return .init(text: "Separating \(Int((p * 100).rounded()))%", tone: .accent, symbol: nil)
        }
        if song.analysisStatus == .failed { return .init(text: "Needs attention", tone: .error, symbol: "exclamationmark.triangle") }
        if song.sourceType == .youtubeLink { return .init(text: "Link only", tone: .neutral, symbol: "link") }
        if song.analysisStatus == .completed || !model.stemKinds(for: song).isEmpty { return .init(text: "Ready", tone: .success, symbol: "checkmark") }
        return .init(text: "Not analysed", tone: .neutral, symbol: nil)
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
    struct Status { let text: String; let tone: DSChip.Tone; let symbol: String? }
    let song: Song
    var status: Status?

    var body: some View {
        HStack(spacing: DS.Space.m) {
            SongCover(song: song, size: 52)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.xs) {
                    Text(song.title).font(DS.Text.body.weight(.semibold)).lineLimit(1)
                    if song.isFavorite { Image(systemName: "star.fill").font(DS.Text.metadata).foregroundStyle(DS.Palette.accent) }
                }
                Text([song.film ?? song.artist, song.language].compactMap { $0 }.joined(separator: " · ").ifEmpty(details))
                    .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: DS.Space.xs)
            if let status { DSChip(text: status.text, symbol: status.symbol, tone: status.tone).fixedSize() }
        }
        .padding(.vertical, DS.Space.xxs)
    }

    private var details: String {
        [song.bpm.map { "\(Int($0.value.rounded())) BPM" }, song.key?.value.displayName].compactMap { $0 }.joined(separator: " · ").ifEmpty("No details")
    }
}

/// The song you were playing: large cover, its tone, and one Play button.
struct ContinueCard: View {
    @EnvironmentObject var model: AppModel
    let song: Song

    var body: some View {
        let tone = model.mainTone(of: song) ?? model.activeArrangement
        let drawings = ToneRow.drawings(tone, library: model.library)
        Button { model.openStudio(song.id) } label: {
            HStack(alignment: .center, spacing: DS.Space.m) {
                SongCover(song: song, size: 96)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("CONTINUE").font(DS.Text.metadata.weight(.semibold)).foregroundStyle(DS.Palette.textSecondary)
                    Text(song.title).font(DS.Text.screenTitle).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                    Text([song.film ?? song.artist, song.key?.value.displayName].compactMap { $0 }.joined(separator: " · "))
                        .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary).lineLimit(1)
                    if let tone {
                        HStack(spacing: DS.Space.xs) {
                            HStack(spacing: -8) { ForEach(drawings, id: \.self) { InstrumentTile(drawing: $0, size: 24) } }
                            Text(tone.name.replacingOccurrences(of: " (My Version)", with: "")).font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill").font(.title3.weight(.bold)).foregroundStyle(DS.Palette.onAccent)
                    .frame(width: 52, height: 52)
                    .background(DS.accentGradient, in: Circle())
                    .shadow(color: DS.Palette.accentGlow, radius: 10, y: 4)
                    .accessibilityHidden(true)
            }
            .padding(DS.Space.m)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous).fill(DS.Palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                        .fill(LinearGradient(colors: [DS.Palette.ambientViolet, DS.Palette.accent.opacity(0.08)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Continue \(song.title)")
        .accessibilityIdentifier("songs.continue")
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
