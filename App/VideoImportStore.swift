import Foundation
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers

struct ImportedVideo: Sendable {
    let url: URL
    let duration: Double
    let width: Double
    let height: Double
}

enum VideoImportError: Error, LocalizedError {
    case unsupported, tooLarge, storageFull
    var errorDescription: String? {
        switch self {
        case .unsupported: return "Choose a playable video up to 30 minutes, with a finite image size up to 8192 pixels."
        case .tooLarge: return "The selected video exceeds the 500 MiB import limit. Trim a copy before importing."
        case .storageFull: return "Managed video storage exceeds 1 GiB. Remove the imported copy before importing another."
        }
    }
}

struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 500 * 1_024 * 1_024 else { throw VideoImportError.tooLarge }
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            do {
                try Task.checkCancellation()
                try FileManager.default.copyItem(at: received.file, to: copy)
                try Task.checkCancellation()
                return PickedMovie(url: copy)
            } catch { try? FileManager.default.removeItem(at: copy); throw error }
        }
    }
}

actor VideoImportStore {
    private func directory() throws -> URL {
        var root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("ImportedVideos", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        return root
    }
    func ingest(_ source: URL) async throws -> ImportedVideo {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 500 * 1_024 * 1_024 else { throw VideoImportError.tooLarge }
        let root = try directory()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])
        let occupied = try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        guard occupied + size <= 1_024 * 1_024 * 1_024 else { throw VideoImportError.storageFull }
        let extensionName = ["mov", "mp4", "m4v"].contains(source.pathExtension.lowercased()) ? source.pathExtension.lowercased() : "mov"
        let target = root.appendingPathComponent(UUID().uuidString + "." + extensionName)
        do {
            try FileManager.default.copyItem(at: source, to: target)
            try Task.checkCancellation()
            let asset = AVURLAsset(url: target)
            let duration = try await asset.load(.duration).seconds
            let playable = try await asset.load(.isPlayable)
            guard playable, duration.isFinite, duration > 0, duration <= 1_800,
                  let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoImportError.unsupported }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let bounds = CGRect(origin: .zero, size: size).applying(transform)
            let width = abs(bounds.width), height = abs(bounds.height)
            guard width.isFinite, height.isFinite, width > 0, height > 0, width <= 8192, height <= 8192 else {
                throw VideoImportError.unsupported
            }
            try Task.checkCancellation()
            return ImportedVideo(url: target, duration: duration, width: Double(width), height: Double(height))
        } catch { try? FileManager.default.removeItem(at: target); throw error }
    }
    func remove(_ url: URL) throws {
        let root = try directory().standardizedFileURL
        guard url.standardizedFileURL.deletingLastPathComponent() == root,
              UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil else { throw VideoImportError.unsupported }
        try FileManager.default.removeItem(at: url)
    }
    func clearManagedCopies() throws {
        let root = try directory()
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            if ["mov", "mp4", "m4v"].contains(file.pathExtension), UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil {
                try remove(file)
            }
        }
    }
}
