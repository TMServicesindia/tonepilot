import AppleArchive
import Foundation
import System

/// Unpacks a downloaded Core ML model (an Apple Archive, LZFSE-compressed, made in CI with
/// `aa archive -d HTDemucs.mlmodelc -o HTDemucs.mlmodelc.aar -a lzfse`) into a folder.
enum ModelArchive {
    enum Failure: LocalizedError {
        case open, extract(String)
        var errorDescription: String? {
            switch self {
            case .open: return "The downloaded model couldn't be opened."
            case .extract(let m): return "The downloaded model couldn't be unpacked (\(m))."
            }
        }
    }

    static func extract(_ archive: URL, to folder: URL) throws {
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let file = ArchiveByteStream.fileStream(path: FilePath(archive.path), mode: .readOnly, options: [],
                                                     permissions: FilePermissions(rawValue: 0o644)) else { throw Failure.open }
        defer { try? file.close() }
        guard let decompress = ArchiveByteStream.decompressionStream(readingFrom: file) else { throw Failure.open }
        defer { try? decompress.close() }
        guard let decode = ArchiveStream.decodeStream(readingFrom: decompress) else { throw Failure.open }
        defer { try? decode.close() }
        guard let extract = ArchiveStream.extractStream(extractingTo: FilePath(folder.path), flags: [.ignoreOperationNotPermitted]) else {
            throw Failure.open
        }
        defer { try? extract.close() }
        do { _ = try ArchiveStream.process(readingFrom: decode, writingTo: extract) } catch {
            throw Failure.extract(error.localizedDescription)
        }
    }
}
