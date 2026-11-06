import SwiftUI
import TonePilotCore

/// The analysis steps the Analysing view lists (screen spec §2.3), in the order the analyser runs them.
/// The analyser returns all results together at the end, so a step shows ✓ when it has run, and the
/// results themselves appear on the Play page when the song is ready.
enum AnalysisStep: Int, CaseIterable {
    case beat, chords, melody, sections, tones, arranging

    var name: String {
        switch self {
        case .beat: return "Beat and tempo"
        case .chords: return "Key and chords"
        case .melody: return "Melody"
        case .sections: return "Sections and hook"
        case .tones: return "Matching tones"
        case .arranging: return "Your arrangement"
        }
    }

    var symbol: String {
        switch self {
        case .beat: return "metronome"
        case .chords: return "music.quarternote.3"
        case .melody: return "waveform.path"
        case .sections: return "square.split.bottomrightquarter"
        case .tones: return "pianokeys"
        case .arranging: return "slider.horizontal.3"
        }
    }

    var id: String {
        switch self {
        case .beat: return "beat"
        case .chords: return "chords"
        case .melody: return "melody"
        case .sections: return "sections"
        case .tones: return "tones"
        case .arranging: return "arrangement"
        }
    }

    /// The step running at pipeline progress `p` (0...1). The fractions follow `SongPipeline` and
    /// `SongAnalyzer`: analysis takes 85% with separated parts (95% without), tone matching to 95%.
    static func current(pipeline p: Double, hasParts: Bool) -> AnalysisStep {
        let share = hasParts ? 0.85 : 0.95
        let a = p / share
        if a < 0.5 { return .beat }
        if a < 0.52 { return .chords }
        if a < 0.88 { return .melody }
        if a < 1 { return .sections }
        if hasParts && p < 0.95 { return .tones }
        return .arranging
    }
}

/// Analysing (Play page while running, spec §2.3): a step list with ✓ for finished steps, the running
/// step highlighted, and Play now once the beat is found. A failed analysis marks the step it stopped at.
struct AnalysisStepList: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let hasParts: Bool

    var body: some View {
        let failed = song.analysisStatus == .failed
        let current = failed ? (model.analysisFailedStep[song.id] ?? 0) : (model.analysisStep[song.id] ?? 0)
        let steps = AnalysisStep.allCases.filter { $0 != .tones || hasParts }
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.m) {
                SongCover(song: song, size: DS.Size.artwork)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(failed ? "Analysis stopped" : "Analysing this song")
                        .font(DS.Text.section).foregroundStyle(DS.Palette.textPrimary)
                    Text(failed ? (song.analysisError ?? "Something went wrong.") : "On this iPhone. You can play the recording now.")
                        .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !failed {
                ProgressView(value: model.analysisProgress[song.id] ?? 0)
                    .tint(DS.Palette.accent)
                    .accessibilityLabel("Analysis progress")
            }
            VStack(spacing: 0) {
                ForEach(steps, id: \.self) { step in
                    row(step, state: state(step, current: current, failed: failed))
                    if step != steps.last { Divider().overlay(DS.Palette.divider).padding(.leading, DS.Size.touchTarget) }
                }
            }
            if failed {
                if model.audioURL(for: song) != nil {
                    Button("Try again") { model.analyze(songId: song.id, useServer: model.serverSettings.enabled) }
                        .buttonStyle(.dsPrimary)
                        .accessibilityIdentifier("analysis.retry")
                }
            } else {
                HStack(spacing: DS.Space.s) {
                    Button("Play now") { if !model.isStudioPlaying { model.studioTogglePlay() } }
                        .buttonStyle(.dsSecondary)
                        .disabled(current == 0 || model.audioURL(for: song) == nil)
                        .accessibilityIdentifier("analysis.playNow")
                    Button("Cancel") { model.cancelAnalysis(songId: song.id) }
                        .buttonStyle(.dsSecondary)
                        .accessibilityIdentifier("analysis.cancel")
                }
            }
        }
        .dsSurface()
    }

    private enum StepState { case done, running, waiting, failed }

    private func state(_ step: AnalysisStep, current: Int, failed: Bool) -> StepState {
        if step.rawValue < current { return .done }
        if step.rawValue == current { return failed ? .failed : .running }
        return .waiting
    }

    private func row(_ step: AnalysisStep, state: StepState) -> some View {
        let tint: Color = {
            switch state {
            case .done: return DS.Palette.success
            case .running: return DS.Palette.accent
            case .waiting: return DS.Palette.textSecondary
            case .failed: return DS.Palette.error
            }
        }()
        let status: String = {
            switch state {
            case .done: return "Done"
            case .running: return "Working…"
            case .waiting: return "Waiting"
            case .failed: return "Stopped here"
            }
        }()
        return HStack(spacing: DS.Space.m) {
            Image(systemName: step.symbol)
                .frame(width: DS.Size.touchTarget - DS.Space.l, height: DS.Size.touchTarget - DS.Space.l)
                .foregroundStyle(tint)
                .background(state == .running ? DS.Palette.accentMuted : DS.Palette.elevated, in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
            Text(step.name).font(DS.Text.body)
                .foregroundStyle(state == .waiting ? DS.Palette.textSecondary : DS.Palette.textPrimary)
            Spacer(minLength: DS.Space.s)
            HStack(spacing: DS.Space.xs) {
                Text(status).font(DS.Text.caption)
                Image(systemName: state == .done ? "checkmark.circle.fill" : (state == .failed ? "exclamationmark.triangle.fill" : (state == .running ? "circle.dotted" : "circle")))
            }
            .foregroundStyle(tint)
        }
        .frame(minHeight: DS.Size.touchTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.name): \(status)")
        .accessibilityIdentifier("analysis.step.\(step.id)")
    }
}
