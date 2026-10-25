import SwiftUI
import TonePilotCore

/// Everything needed to play one section: what's heard, the tone to use, left-hand Root → Fifth →
/// Root pattern, right-hand phrases and chord voicings, and a practice loop at slower speeds.
struct SectionGuideView: View {
    @EnvironmentObject var model: AppModel
    let songId: UUID
    let sectionId: UUID
    @State private var speed: Float = 0.75

    var body: some View {
        if let song = model.song(songId), let section = song.sections.first(where: { $0.id == sectionId }) {
            let ordered = song.orderedSections
            let index = ordered.firstIndex { $0.id == sectionId } ?? 0
            let guide = KeyboardGuide.build(song: song, section: section, previous: index > 0 ? ordered[index - 1] : nil, library: model.library)
            List {
                Section {
                    HStack {
                        Text("\(section.startTime.mmss) – \(section.endTime.mmss)").font(.headline.monospacedDigit())
                        if section.isClimax == true { Text("CLIMAX").font(.caption2.bold()).padding(.horizontal, 6).background(Theme.accent.opacity(0.3), in: Capsule()) }
                        Spacer()
                        if section.provenance != .user { ConfidenceBadge(confidence: section.confidence, provenance: section.provenance) }
                    }
                    Text(guide.changes.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }

                Section("Practice") {
                    if model.audioURL(for: song) != nil {
                        Picker("Speed", selection: $speed) {
                            Text("50%").tag(Float(0.5)); Text("75%").tag(Float(0.75)); Text("90%").tag(Float(0.9)); Text("100%").tag(Float(1))
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Button { model.practice(songId: songId, sectionId: sectionId, rate: speed) } label: { Label("Loop this section", systemImage: "repeat") }
                                .buttonStyle(.borderedProminent)
                            if model.isSectionPlaying {
                                Button { model.stopBackingTrack() } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(.bordered)
                            }
                        }
                        if speed != 1 { Text("Generated bass/drums pause below 100% speed; your tones always play.").font(.caption2).foregroundStyle(.secondary) }
                    } else {
                        Text("No audio file for this song — use the guide below with the metronome in Play.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(guide.practiceSteps.enumerated()), id: \.offset) { i, step in
                        Text("\(i + 1). \(step)").font(.subheadline)
                    }
                }

                Section("Tone") {
                    Text(guide.toneAdvice).font(.subheadline)
                    Button { model.activateSection(sectionId) } label: { Label("Use this tone on my keyboard", systemImage: "pianokeys") }
                    if let a = section.activity, !a.isEmpty {
                        Text("Heard here").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(a.enumerated()), id: \.offset) { _, act in
                            HStack(alignment: .top) {
                                Text("\(act.role.displayName)").frame(width: 130, alignment: .leading)
                                Text("\(Int(act.level * 100))%").font(.caption.monospacedDigit()).frame(width: 40)
                                Text(act.evidence).font(.caption).foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                Section("Left hand · Root → Fifth → Root") {
                    Text(guide.leftHandPattern)
                    if !guide.leftHandExample.isEmpty { Text(guide.leftHandExample).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    if !guide.chords.isEmpty { Text("Chords: " + guide.chords.joined(separator: " – ")).font(.subheadline.monospaced()) }
                    if !guide.rootMovement.isEmpty { Text("Bass movement heard: \(guide.rootMovement)").font(.caption).foregroundStyle(.secondary) }
                }

                Section("Right hand") {
                    if let range = guide.melodyRange { Text("Melody range: \(range)") }
                    if guide.phrases.isEmpty { Text("No clear melody in this section.").foregroundStyle(.secondary) }
                    ForEach(Array(guide.phrases.enumerated()), id: \.offset) { i, phrase in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Phrase \(i + 1) · \(phrase.start.mmss)\(phrase.hasOrnaments ? " · 〰︎" : "")").font(.caption).foregroundStyle(.secondary)
                            Text(phrase.keys.joined(separator: " ")).font(.subheadline.monospaced())
                        }
                    }
                    if !guide.voicings.isEmpty {
                        DisclosureGroup("Chord shapes for fills (with inversions)") {
                            ForEach(Array(guide.voicings.enumerated()), id: \.offset) { _, v in
                                HStack {
                                    Text(v.chord).font(.headline).frame(width: 50, alignment: .leading)
                                    Text(v.notes.joined(separator: " ")).font(.subheadline.monospaced())
                                    Spacer()
                                    Text(v.inversion).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !guide.instructions.isEmpty {
                    Section("How to play this section") {
                        ForEach(guide.instructions, id: \.self) { Text("• " + $0).font(.subheadline) }
                    }
                }

                Section {
                    HStack {
                        if index > 0 { NavigationLink("‹ \(ordered[index - 1].label)") { SectionGuideView(songId: songId, sectionId: ordered[index - 1].id) } }
                        Spacer()
                        if index + 1 < ordered.count { NavigationLink("\(ordered[index + 1].label) ›") { SectionGuideView(songId: songId, sectionId: ordered[index + 1].id) } }
                    }
                }
            }
            .navigationTitle(section.label)
        } else {
            ContentUnavailableView("Section not found", systemImage: "questionmark")
        }
    }
}
