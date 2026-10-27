import CoreMedia
import Foundation
import SoundAnalysis
import TonePilotCore

/// Which instruments play in each section, heard with Apple's on-device sound classifier
/// (300+ sound classes, nothing downloaded or uploaded). Runs on the separated instrument parts
/// when they exist (the singer doesn't mask the brass or synth), else on the full recording.
/// Off the main thread only (it reads the whole file).
enum InstrumentRecognizer {
    /// Section id → instrument family (`InstrumentEvidence.families`) → 0...1 (mean confidence).
    static func recognize(files: [URL], sections: [SongSection]) -> [UUID: [String: Double]] {
        guard !files.isEmpty, !sections.isEmpty else { return [:] }
        let ordered = sections.sorted { $0.startTime < $1.startTime }
        var best: [UUID: [String: Double]] = [:]
        for url in files {
            guard let heard = classify(url, sections: ordered) else { continue }
            // Across parts, a family counts as strongly as the part where it's clearest.
            for (id, families) in heard { best[id, default: [:]].merge(families) { max($0, $1) } }
        }
        return best
    }

    private static func classify(_ url: URL, sections: [SongSection]) -> [UUID: [String: Double]]? {
        do {
            let analyzer = try SNAudioFileAnalyzer(url: url)
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.overlapFactor = 0.25
            let observer = Observer(sections: sections)
            try analyzer.add(request, withObserver: observer)
            analyzer.analyze()
            return observer.result()
        } catch {
            return nil
        }
    }

    private final class Observer: NSObject, SNResultsObserving {
        let sections: [SongSection]
        private var sums: [UUID: [String: Double]] = [:]
        private var windows: [UUID: Int] = [:]
        private let lock = NSLock()

        init(sections: [SongSection]) { self.sections = sections }

        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let r = result as? SNClassificationResult else { return }
            let mid = r.timeRange.start.seconds + r.timeRange.duration.seconds / 2
            guard mid.isFinite, let section = sections.last(where: { $0.startTime <= mid }), mid < section.endTime else { return }
            // Strongest label per family in this window.
            var window: [String: Double] = [:]
            for c in r.classifications where c.confidence > 0.05 {
                if let family = InstrumentEvidence.family(forLabel: c.identifier) {
                    window[family] = max(window[family] ?? 0, c.confidence * InstrumentEvidence.weight(forLabel: c.identifier))
                }
            }
            lock.withLock {
                windows[section.id, default: 0] += 1
                for (f, v) in window { sums[section.id, default: [:]][f, default: 0] += v }
            }
        }

        func result() -> [UUID: [String: Double]] {
            lock.withLock {
                var out: [UUID: [String: Double]] = [:]
                for (id, families) in sums {
                    let n = Double(max(1, windows[id] ?? 1))
                    let mean = families.mapValues { min(1, $0 / n) }.filter { $0.value >= 0.03 }
                    if !mean.isEmpty { out[id] = mean }
                }
                return out
            }
        }
    }
}
