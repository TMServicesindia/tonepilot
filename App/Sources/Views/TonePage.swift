import SwiftUI
import TonePilotCore

// The Tone page (screen spec §2.6 / mockup v9 #8): the suggestion first — what TonePilot chose, why (one
// plain sentence), Change / Compare — then the scope (whole song / per section) and the layers with
// working level sliders. Identifiers kept from the previous card: tone.editMain, tone.compare,
// tone.hookSource, tone.fusion, tonemode.*.

struct MyKeyboardCard: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let onChangeSound: (UUID) -> Void
    let onEditSound: (UUID) -> Void
    let onEditTone: (UUID) -> Void
    var onCompare: () -> Void = {}

    var body: some View {
        let usingMain = model.isUsingMainTone(song)
        let sectionId = model.activeSectionId ?? song.orderedSections.first?.id
        // The tone you edit here: the main tone, or this section's own (editable) version.
        // (Read-only here: the editable copy of a section's tone is made only when you change something.)
        let sectionTone = sectionId.flatMap { id in song.sections.first { $0.id == id } }.flatMap { song.arrangement(for: $0) }
        let tone: Arrangement? = usingMain ? model.mainTone(of: song) : (sectionTone ?? model.activeArrangement)
        VStack(alignment: .leading, spacing: DS.Space.m) {
            ConnectionChips()
            ToneSuggestionCard(song: song, tone: tone, usingMain: usingMain, sectionId: sectionId,
                               onChange: {
                                   if usingMain, let t = tone { onEditTone(t.id) } else if let s = sectionId { onChangeSound(s) }
                               },
                               onCompare: onCompare)
            if !song.sections.isEmpty { ToneModeSwitch(song: song) }
            DSSectionHeader(title: "Layers", action: (title: "Edit", id: usingMain ? "tone.editMain" : "tone.editSection", run: {
                if usingMain, let t = tone { onEditTone(t.id) } else if let s = sectionId { onEditSound(s) }
            }))
            if let tone {
                VStack(spacing: 0) {
                    ForEach(Array(tone.layers.enumerated()), id: \.element.id) { i, layer in
                        LayerLevelRow(tone: tone, index: i, songId: song.id, sectionId: usingMain ? nil : sectionId)
                        if i < tone.layers.count - 1 { Divider().overlay(DS.Palette.divider).padding(.leading, 68) }
                    }
                }
                .dsSurface(padding: 0)
            }
            if let track = model.studioTracks(for: song).first(where: { $0.id == SongStudio.keyboard }) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Your keys' volume").font(DS.Text.label).foregroundStyle(DS.Palette.textPrimary)
                    TrackRow(track: track, songId: song.id, showHeader: false)
                }
                .dsSurface()
            }
            if !usingMain, !song.sections.isEmpty { SectionSwitchingOptions(song: song) }
        }
    }
}

/// Keyboard and speaker status as quiet chips (instructions live in Settings › Keyboard connection).
private struct ConnectionChips: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let noKeyboard = model.midi.sources.isEmpty
        let speaker = AudioSessionSetup.isBuiltInSpeaker
        if noKeyboard || speaker {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s) { chips(noKeyboard, speaker); Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: DS.Space.xs) { chips(noKeyboard, speaker) }
            }
        }
    }

    @ViewBuilder private func chips(_ noKeyboard: Bool, _ speaker: Bool) -> some View {
        if noKeyboard { DSChip(text: "Casio not connected", symbol: "pianokeys", tone: .accent).fixedSize() }
        if speaker { DSChip(text: "Playing on the iPhone speaker", symbol: "speaker.wave.2", tone: .neutral).fixedSize() }
    }
}

/// What TonePilot chose and why, with Change / Compare.
private struct ToneSuggestionCard: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let tone: Arrangement?
    let usingMain: Bool
    let sectionId: UUID?
    let onChange: () -> Void
    let onCompare: () -> Void

    var body: some View {
        let hook = song.understanding?.hook
        let hookSection = hook.flatMap { h in song.sections.first { $0.id == h.sectionId } }
        let section = sectionId.flatMap { id in song.sections.first { $0.id == id } }
        let drawings = ToneRow.drawings(tone, library: model.library)
        let names = (tone?.layers.filter { !$0.muted } ?? []).compactMap { model.library.patch(id: $0.patchId)?.name }
        let inUse = tone.map { $0.id == model.activeArrangement?.id } ?? false
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack {
                if usingMain, hook != nil {
                    DSChip(text: hook?.chosenByUser == true ? "From the section you chose" : "Suggested for the hook", symbol: "sparkles", tone: .accent)
                } else if usingMain {
                    DSChip(text: "One tone for the whole song", symbol: "music.note", tone: .accent)
                } else {
                    DSChip(text: "Tone for \(section?.label ?? "this section")", symbol: "music.note", tone: .accent)
                }
                Spacer()
                if inUse { DSChip(text: "In use", symbol: "checkmark", tone: .success) }
            }
            HStack(alignment: .center, spacing: DS.Space.l) {
                ZStack(alignment: .bottomTrailing) {
                    InstrumentTile(drawing: drawings.first ?? .piano, size: 96)
                    if drawings.count > 1 {
                        InstrumentTile(drawing: drawings[1], size: 42)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DS.Palette.surface, lineWidth: 3))
                            .offset(x: 14, y: 10)
                    }
                }
                .padding(.trailing, drawings.count > 1 ? 12 : 0)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(tone?.name.replacingOccurrences(of: " (My Version)", with: "") ?? "No tone yet")
                        .font(DS.Text.screenTitle).foregroundStyle(DS.Palette.textPrimary).lineLimit(2).minimumScaleFactor(0.8)
                    if !names.isEmpty {
                        Text(names.joined(separator: " + ")).font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary).lineLimit(2)
                    }
                }
            }
            if let why = whySentence(hook: hook, hookSection: hookSection) {
                (Text("Why: ").bold() + Text(why))
                    .font(DS.Text.bodySecondary).foregroundStyle(DS.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if usingMain, hookSection != nil { hookMenu }
            // Side by side; stacked at large text sizes so labels never break mid-word.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s) { actionButtons }
                VStack(spacing: DS.Space.s) { actionButtons }
            }
            FusionLine(song: song)
        }
        .padding(DS.Space.componentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                .fill(LinearGradient(colors: [DS.Palette.accent.opacity(0.10), DS.Palette.surface.opacity(0)], startPoint: .top, endPoint: .center))
                .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
        )
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous).strokeBorder(DS.Palette.accent.opacity(0.28), lineWidth: 1))
        .accessibilityIdentifier("tone.card")
    }

    @ViewBuilder private var actionButtons: some View {
        Button(action: onChange) { Label("Change", systemImage: "arrow.triangle.2.circlepath").fixedSize() }
            .buttonStyle(.dsSecondary)
            .accessibilityIdentifier("tone.change")
        if usingMain {
            Button(action: onCompare) { Label("Compare", systemImage: "ear").fixedSize() }
                .buttonStyle(.dsSecondary)
                .accessibilityIdentifier("tone.compare")
        }
    }

    /// One plain sentence: where the tone comes from. No scores.
    private func whySentence(hook: SongUnderstanding.Hook?, hookSection: SongSection?) -> String? {
        guard usingMain, let hook, let hs = hookSection else { return nil }
        if hook.chosenByUser { return "built from \(hs.label), the section you chose." }
        let repeats = song.sections.filter { $0.repetitionGroup != nil && $0.repetitionGroup == hs.repetitionGroup && $0.type == hs.type }.count
        var s = "the song's hook is \(hs.label)" + (repeats > 1 ? ", heard \(repeats)×" : "")
        s += hook.kind == .bgm ? " — an instrumental line with no singing over it." : "."
        if let f = song.fusion, f.isCurrent(song), f.mainEntry(song)?.agreement == .same { s += " Both separations agree." }
        return s
    }

    private var hookMenu: some View {
        Menu {
            ForEach(song.orderedSections.filter { s in !song.orderedSections.contains { $0.id != s.id && $0.repetitionGroup != nil && $0.repetitionGroup == s.repetitionGroup && $0.type == s.type && $0.startTime < s.startTime } }) { s in
                Button(s.label) { model.setHook(s.id, songId: song.id) }
            }
        } label: {
            Label("Use another section as the hook", systemImage: "music.note.list")
                .font(DS.Text.caption.weight(.semibold)).foregroundStyle(DS.Palette.accent)
                .frame(minHeight: DS.Size.touchTarget)
        }
        .accessibilityIdentifier("tone.hookSource")
    }
}

/// One layer: drawing, name and a working level slider (saved when you let go).
private struct LayerLevelRow: View {
    @EnvironmentObject var model: AppModel
    let tone: Arrangement
    let index: Int
    let songId: UUID
    /// Per-section mode: the section whose tone this is (its AI original is copied to My Version on edit).
    let sectionId: UUID?
    @State private var level: Double = 0
    @State private var editing = false

    var body: some View {
        let layer = tone.layers[index]
        let patch = model.library.patch(id: layer.patchId)
        HStack(spacing: DS.Space.m) {
            InstrumentTile(drawing: patch.map { InstrumentDrawing.forFamily($0.family) } ?? .piano, size: 42)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack {
                    Text(patch?.name ?? "Sound").font(DS.Text.body.weight(.semibold)).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                    if layer.muted { DSChip(text: "Muted") }
                    Spacer()
                    Text("\(Int((editing ? level : layer.volume) * 100))%").font(DS.Text.numericSmall).foregroundStyle(DS.Palette.textSecondary)
                }
                Slider(value: $level, in: 0...1) { isEditing in
                    editing = isEditing
                    if !isEditing { commit() }
                }
                .tint(DS.Palette.accent)
                .accessibilityLabel("\(patch?.name ?? "Layer") level")
                .accessibilityValue("\(Int(level * 100)) percent")
                .accessibilityIdentifier("tone.layer.level.\(index)")
            }
        }
        .padding(.horizontal, DS.Space.m).padding(.vertical, DS.Space.s)
        .onAppear { level = layer.volume }
        .onChange(of: layer.volume) { _, v in if !editing { level = v } }
        .accessibilityIdentifier("tone.layer.\(index)")
    }

    private func commit() {
        guard tone.layers.indices.contains(index), abs(tone.layers[index].volume - level) > 0.001 else { return }
        var a = tone
        if a.origin == .aiOriginal {
            // AI originals stay unchanged; the edit goes to the section's own My Version.
            guard let sectionId, let mine = model.editableTone(songId: songId, sectionId: sectionId) else { return }
            a = mine
        }
        guard a.layers.indices.contains(index) else { return }
        a.layers[index].volume = level
        model.updateArrangement(a, inSong: songId)
    }
}

/// Per-section mode: follow the song automatically, or confirm each switch.
private struct SectionSwitchingOptions: View {
    @EnvironmentObject var model: AppModel
    let song: Song

    var body: some View {
        let switching = song.switching ?? SwitchingSettings()
        VStack(spacing: DS.Space.s) {
            Toggle(isOn: Binding(get: { switching.mode == .automatic },
                                 set: { auto in
                                     var s = switching
                                     s.mode = auto ? .automatic : .assisted
                                     if model.audioURL(for: song) == nil, s.reference == .backingTrack { s.reference = .timer }
                                     model.updateSwitching(s)
                                 })) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Switch automatically").font(DS.Text.body)
                    Text(switching.mode == .automatic ? "Follows the song." : "Tap to switch at each section.")
                        .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .tint(DS.Palette.accent)
            if let id = model.pendingSuggestion, let next = song.sections.first(where: { $0.id == id }) {
                Button { model.confirmSuggestion() } label: { Label("Switch to \(next.label)", systemImage: "arrow.right.circle.fill") }
                    .buttonStyle(.dsPrimary)
            }
        }
        .dsSurface()
    }
}
