import Foundation
import TonePilotCore
import UIKit

/// P3.3: 4-part + 6-part fusion. After the first separation and its analysis, the song is separated
/// again with the other model in the background, its parts are matched the same way, and both sets
/// of matches are compared (`PartFusion`): agreement raises confidence, disagreement shows both tones
/// so you can choose. The second model's parts are deleted afterwards (only its matches are kept).
extension AppModel {
    /// The model that made the song's separated parts (nil = not separated on this iPhone).
    func separatedPack(_ song: Song) -> SeparationPack? {
        guard let stems = song.stems, stems.contains(where: { $0.model.contains("on this iPhone") }) else { return nil }
        return stems.contains { $0.kind == .piano || $0.kind == .guitar || $0.model.contains("6s") } ? .six : .four
    }

    func isFusing(_ songId: UUID) -> Bool { fusionProgress[songId] != nil }

    /// Starts the second separation when it's useful: fusion on, the song separated here and matched,
    /// nothing else separating, and no current fusion for these matches.
    func startFusionIfNeeded(_ songId: UUID) {
        guard fusionEnabled, let song = song(songId), let primary = separatedPack(song), song.partMatches?.isEmpty == false,
              !isFusing(songId), fusionProgress.isEmpty, pendingSeparation == nil, separationProgress.isEmpty, analysisProgress[songId] == nil else { return }
        if let f = song.fusion {
            if f.isCurrent(song) { return }
            // Re-analysed: compare the new matches with the other model's (kept) ones when its sections still exist.
            let other = primary == .four ? f.six : f.quiet
            let ids = Set(song.sections.map(\.id.uuidString))
            if other.sectionLeads.keys.allSatisfy(ids.contains) {
                finishFusion(songId, primary: primary, current: song, other: other)
                return
            }
        }
        let pack: SeparationPack = primary == .four ? .six : .four
        guard modelDownloadProgress[pack] == nil else { return }
        if models.isInstalled(pack) { runFusion(songId, primary: primary, pack: pack); return }
        downloadModel(pack) { [weak self] ok in if ok { self?.runFusion(songId, primary: primary, pack: pack) } }
    }

    func cancelFusion(_ songId: UUID) {
        fusionCancels.set(songId)
        fusionProgress[songId] = nil
    }

    private func runFusion(_ songId: UUID, primary: SeparationPack, pack: SeparationPack) {
        guard fusionEnabled, !isFusing(songId), separationProgress.isEmpty, let song = song(songId), let url = audioURL(for: song) else { return }
        StemSeparator.current = models.weightsURL(pack)
        CoreMLNetwork.current = models.coreMLURL(pack)
        fusionProgress[songId] = 0
        fusionError[songId] = nil
        fusionCancels.clear(songId)
        let dir = store.stemDirectory(for: songId).appendingPathComponent("fusion-\(pack.rawValue)", isDirectory: true)
        let cancels = fusionCancels
        let snapshot = song
        let splitLead = song.partMatches?[StemInfo.Kind.lead.rawValue] != nil   // compare like with like
        let patches = library.patches
        let loadedBank = cache.loadedBank(named: FactoryPatches.defaultSoundFontFile)
        let bankURL = store.soundFontDirectory.appendingPathComponent(FactoryPatches.defaultSoundFontFile)
        let parts = pack == .six ? 6 : 4
        let throttle = ProgressThrottle()
        let report: @Sendable (Double) -> Void = { [weak self] p in
            if throttle.shouldSend(p) { Task { @MainActor in if self?.fusionProgress[songId] != nil { self?.fusionProgress[songId] = p } } }
        }
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "Second separation") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        let thread = Thread { [weak self] in
            var set: PartFusion.MatchSet?
            var failure: String?
            autoreleasepool {
                defer { try? FileManager.default.removeItem(at: dir) }   // only the matches are kept
                do {
                    let stems = try StemSeparator.separate(input: url, outputDir: dir, progress: { report($0 * 0.8) },
                                                           isCancelled: { cancels.contains(songId) })
                    var files: [StemInfo.Kind: URL] = [:]
                    for s in stems { files[s.kind] = dir.appendingPathComponent(s.fileName) }
                    if splitLead, let music = files[.other] {
                        let (l, r) = try StemSeparator.decodeStereo(music)
                        if let split = LeadSplitter.split(channels: [l, r], sampleRate: StemSeparator.sampleRate, progress: { p in
                            report(0.8 + 0.05 * p); return !cancels.contains(songId)
                        }) {
                            try StemSeparator.writeStem(left: split.lead[0], right: split.lead[1], to: dir.appendingPathComponent("lead.m4a"))
                            try StemSeparator.writeStem(left: split.backing[0], right: split.backing[1], to: dir.appendingPathComponent("backing.m4a"))
                            files[.lead] = dir.appendingPathComponent("lead.m4a")
                            files[.backing] = dir.appendingPathComponent("backing.m4a")
                            files[.other] = nil
                        }
                    }
                    if cancels.contains(songId) { throw StemSeparator.Failure.cancelled }
                    // The instrument parts only (the matcher doesn't use vocals / drums / bass).
                    let kinds: Set<StemInfo.Kind> = [.lead, .backing, .other, .piano, .guitar]
                    files = files.filter { kinds.contains($0.key) }
                    var audio: [StemInfo.Kind: TonePilotCore.AudioBuffer] = [:]
                    for (kind, file) in files { audio[kind] = try AudioFileDecoder.decodeMono(url: file) }
                    let bank = loadedBank ?? (try? SoundFontBank(url: bankURL))
                    let perceptual = PerceptualToneService.shared.hook(stemFiles: files)
                    set = PartFusion.matchSet(parts: parts, song: snapshot, stems: audio, patches: patches,
                                              instrument: PartMatcher.loader(bank: bank), perceptual: perceptual) { p in
                        report(0.85 + 0.15 * p)
                        return !cancels.contains(songId)
                    }
                    if cancels.contains(songId) { throw StemSeparator.Failure.cancelled }
                } catch {
                    if case StemSeparator.Failure.cancelled = error { return }
                    failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
            let result = set, failureText = failure
            Task { @MainActor in
                guard let self else { return }
                if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
                let wasRunning = self.fusionProgress[songId] != nil
                self.fusionProgress[songId] = nil
                if let failureText { self.fusionError[songId] = "Second separation: \(failureText)" }
                if wasRunning, let result, let current = self.song(songId) {
                    // The song was re-analysed meanwhile: these matches belong to other sections.
                    if current.partMatches == snapshot.partMatches, current.sectionLeadMatches == snapshot.sectionLeadMatches {
                        self.finishFusion(songId, primary: primary, current: current, other: result)
                    }
                }
                if let next = self.pendingSeparation { self.pendingSeparation = nil; self.separateStems(next) }
            }
        }
        // Same priority as the first separation (performance cores); it starts only when that one is done.
        thread.qualityOfService = .userInitiated
        thread.stackSize = 8 << 20
        thread.start()
    }

    /// Combines the song's current matches (from `primary`) with the other model's, applies the fused
    /// default (or your earlier choice) and rebuilds the tones.
    func finishFusion(_ songId: UUID, primary: SeparationPack, current: Song, other: PartFusion.MatchSet) {
        var song = current
        let mine = PartFusion.MatchSet(parts: primary == .six ? 6 : 4, matches: song.partMatches ?? [:], sectionLeads: song.sectionLeadMatches ?? [:])
        let choice = song.fusion?.choice ?? .fused
        song.fusion = primary == .four ? PartFusion.fuse(quiet: mine, six: other, patches: library.patches, choice: choice)
                                       : PartFusion.fuse(quiet: other, six: mine, patches: library.patches, choice: choice)
        applyFusion(choice, to: &song)
    }

    /// Uses the 4-part, 6-part or fused matches for the song and rebuilds its AI tones (yours are kept).
    func setFusionChoice(_ choice: PartFusion.Choice, songId: UUID) {
        guard var song = song(songId), song.fusion != nil else { return }
        applyFusion(choice, to: &song)
    }

    /// Rebuilding the tones runs off the main thread; the song is saved when it's done (unless it changed meanwhile).
    private func applyFusion(_ choice: PartFusion.Choice, to song: inout Song) {
        PartFusion.apply(choice, to: &song)
        update(song)   // the choice shows right away
        let snapshot = song, patches = library.patches
        Task.detached(priority: .userInitiated) { [weak self] in
            let arranged = AutoArranger.arrange(snapshot, patches: patches).song
            await MainActor.run {
                guard let self, let now = self.song(snapshot.id), now.fusion == snapshot.fusion,
                      now.partMatches == snapshot.partMatches, now.sections.map(\.id) == snapshot.sections.map(\.id) else { return }
                self.update(arranged)
                if self.activeSongId == arranged.id { self.startPerformance(songId: arranged.id) }
            }
        }
    }
}
