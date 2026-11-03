import Foundation
import TonePilotCore

/// Real-instrument sound packs (phase 1): download / delete, and keeping the library and the
/// nearest-sound search in step with what is installed.
extension AppModel {
    /// Reads the installed packs off the main thread, then adds their tones to the library (and
    /// removes tones of packs that are gone) and gives their embeddings to the sound search.
    func refreshSoundPacks() {
        let store = soundPacks
        Task.detached(priority: .utility) { [weak self] in
            let packs = store.installed()
            await MainActor.run { self?.applySoundPacks(packs) }
        }
    }

    func applySoundPacks(_ packs: [SoundPack]) {
        let installedIds = Set(packs.map(\.id))
        let before = library.patches
        library.patches.removeAll { p in
            guard let tags = p.tags, tags.contains("sound-pack") else { return false }
            return !tags.contains(where: installedIds.contains)
        }
        for pack in packs { for patch in pack.patches { library.upsert(patch) } }
        if library.patches != before { save() }
        installedSoundPacks = packs.map(\.id)
        installedSoundPackVersions = Dictionary(packs.map { ($0.id, $0.version) }, uniquingKeysWith: { a, _ in a })
        PerceptualToneService.shared.setPackEntries(harmonic: packs.flatMap { $0.embeddings?.harmonic ?? [] },
                                                    plain: packs.flatMap { $0.embeddings?.plain ?? [] })
    }

    /// The published pack list (for Settings).
    func loadSoundPackList() {
        let store = soundPacks
        Task.detached(priority: .utility) { [weak self] in
            let result: Result<[SoundPackStore.Manifest.Pack], Error>
            do { result = .success(try await store.manifest().packs.values.sorted { $0.name < $1.name }) } catch { result = .failure(error) }
            await MainActor.run {
                switch result {
                case .success(let list): self?.soundPackList = list; self?.soundPackError = nil
                case .failure(let e): self?.soundPackError = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
                }
            }
        }
    }

    func downloadSoundPack(_ info: SoundPackStore.Manifest.Pack) {
        guard soundPackProgress[info.id] == nil else { return }
        soundPackError = nil
        soundPackProgress[info.id] = 0
        let store = soundPacks
        let throttle = ProgressThrottle()
        Task.detached(priority: .userInitiated) { [weak self] in
            var failure: String?
            do {
                _ = try await store.install(info) { p in
                    if throttle.shouldSend(p) { Task { @MainActor in if self?.soundPackProgress[info.id] != nil { self?.soundPackProgress[info.id] = p } } }
                }
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            let failureText = failure
            await MainActor.run {
                self?.soundPackProgress[info.id] = nil
                self?.soundPackError = failureText
                self?.refreshSoundPacks()
            }
        }
    }

    func deleteSoundPack(_ id: String) {
        guard soundPackProgress[id] == nil else { return }
        soundPacks.delete(id)
        refreshSoundPacks()
    }
}
