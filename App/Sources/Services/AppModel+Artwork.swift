import AVFoundation
import Foundation
import TonePilotCore
import UIKit

/// Song covers, step 1: the artwork embedded in the song's own file (ID3 APIC / MP4 `covr`), read on this
/// iPhone, never downloaded. Decoded off the main thread, downscaled and cached under Artwork/<id>.jpg;
/// songs without artwork get a "<id>.none" marker so the file is read only once.
extension AppModel {
    var artworkDirectory: URL { store.rootDirectory.appendingPathComponent("Artwork", isDirectory: true) }

    func loadArtwork(for song: Song) {
        guard artworks[song.id] == nil, !artworkRequested.contains(song.id) else { return }
        artworkRequested.insert(song.id)
        let dir = artworkDirectory
        let cached = dir.appendingPathComponent("\(song.id.uuidString).jpg")
        let none = dir.appendingPathComponent("\(song.id.uuidString).none")
        let audio = audioURL(for: song)
        let id = song.id
        Task.detached(priority: .utility) { [weak self] in
            if FileManager.default.fileExists(atPath: none.path) { return }
            var image = UIImage(contentsOfFile: cached.path)
            if image == nil, let audio {
                let asset = AVURLAsset(url: audio)
                let items = (try? await asset.load(.commonMetadata)) ?? []
                let art = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork).first
                if let data = try? await art?.load(.dataValue), let full = UIImage(data: data) {
                    image = Self.downscaled(full, to: 600)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try? image?.jpegData(compressionQuality: 0.85)?.write(to: cached)
                } else {
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    FileManager.default.createFile(atPath: none.path, contents: nil)
                }
            }
            guard let image else { return }
            await MainActor.run { self?.artworks[id] = image }
        }
    }

    nonisolated static func downscaled(_ image: UIImage, to side: CGFloat) -> UIImage {
        let scale = min(1, side / max(image.size.width, image.size.height))
        guard scale < 1 else { return image }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
