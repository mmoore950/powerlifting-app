import Foundation
import CryptoKit

enum AnnotationExportError: Error, LocalizedError {
    case busy, state, identity, files, budget, space, leased
    var errorDescription: String? {
        switch self {
        case .busy: return "Save or discard the prepared annotation export before preparing another."
        case .state: return "Choose a positive annotation window of at most one second."
        case .identity: return "The movie or capture files changed. Prepare a new export."
        case .files: return "The annotation package is incomplete or unreadable."
        case .budget: return "The annotation package exceeds its file, size or processing limit."
        case .space: return "There is not enough free space to prepare this movie export."
        case .leased: return "Finish or cancel the Files dialog before discarding this export."
        }
    }
}

struct PreparedAnnotationExport: Sendable, Identifiable {
    let id: UUID, directory: URL
    let sourceBytes: Int, packageBytes: Int
}
struct AnnotationExportWork: Sendable {
    let id: UUID, directory: URL, capture: URL
    let mediaURL: URL, sourceBytes: Int, sourceSHA256: String
}
private struct AnnotationExportFile: Codable, Sendable {
    let path: String, bytes: Int, sha256: String
}
private struct AnnotationExportReceipt: Codable, Sendable {
    let schemaVersion: Int, id: UUID, sourceName: String, sourceSHA256: String
    let sourceBytes: Int, packageBytes: Int
    let files: [AnnotationExportFile]
}

/// The only owned roots are AnnotationExports/.annotation-work-UUID and
/// AnnotationExports/annotation-UUID. Never removes a Files destination or movie.
actor AnnotationExportStore {
    static let shared = AnnotationExportStore()
    static let packageLimit = 600 * 1024 * 1024
    private static let captureLimit = 82 * 1024 * 1024
    private let rootDirectory: URL?
    private let capacity: @Sendable (URL) throws -> Int64?
    private let copyChunkObserver: (@Sendable (URL, Int) -> Void)?
    private var initialized = false
    private var activeWork: AnnotationExportWork?
    private var workCleanupFailed = false
    private var prepared: PreparedAnnotationExport?
    private var leased = false

    init(rootDirectory: URL? = nil,
         capacity: @escaping @Sendable (URL) throws -> Int64? = {
             try $0.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
         }, copyChunkObserver: (@Sendable (URL, Int) -> Void)? = nil) {
        self.rootDirectory = rootDirectory; self.capacity = capacity
        self.copyChunkObserver = copyChunkObserver
    }
    private func root() throws -> URL {
        var root = try rootDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("AnnotationExports", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw AnnotationExportError.files }
        // Prepared movies must survive cache purging while Files holds a lease.
        // Local preparation does not opt the footage into cloud backup.
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        return root.standardizedFileURL
    }
    private func removeInactiveWork() throws {
        guard activeWork == nil else { throw AnnotationExportError.busy }
        let entries = try FileManager.default.contentsOfDirectory(at: root(), includingPropertiesForKeys: [.isSymbolicLinkKey])
        for entry in entries where entry.lastPathComponent.hasPrefix(".annotation-work-") {
            try owned(entry, prefix: ".annotation-work-")
            try FileManager.default.removeItem(at: entry)
        }
    }
    private func owned(_ url: URL, prefix: String) throws {
        guard url.standardizedFileURL.deletingLastPathComponent() == (try root()),
              url.lastPathComponent.hasPrefix(prefix),
              UUID(uuidString: String(url.lastPathComponent.dropFirst(prefix.count))) != nil,
              try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw AnnotationExportError.files }
    }
    private func initialize() throws {
        guard !initialized else { return }
        let directory = try root()
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])
        for entry in entries where entry.lastPathComponent.hasPrefix(".annotation-work-") {
            try owned(entry, prefix: ".annotation-work-")
            try FileManager.default.removeItem(at: entry)
        }
        let completed = entries.filter { $0.lastPathComponent.hasPrefix("annotation-") }
        guard completed.count <= 1 else { throw AnnotationExportError.busy }
        if let entry = completed.first {
            try owned(entry, prefix: "annotation-")
            let receipt = try readReceipt(entry)
            guard entry.lastPathComponent == "annotation-" + receipt.id.uuidString else { throw AnnotationExportError.files }
            prepared = PreparedAnnotationExport(id: receipt.id, directory: entry,
                sourceBytes: receipt.sourceBytes, packageBytes: receipt.packageBytes + (try regularSize(entry.appendingPathComponent("export-receipt.json"), limit: 64 * 1024)))
        }
        initialized = true
    }
    func recover() throws -> PreparedAnnotationExport? { try initialize(); return prepared }
    private func requireSpace(_ directory: URL, bytes: Int) throws {
        if let free = try capacity(directory), free < Int64(bytes) { throw AnnotationExportError.space }
    }
    func begin(mediaURL: URL) throws -> AnnotationExportWork {
        try initialize()
        guard prepared == nil, activeWork == nil, !leased else { throw AnnotationExportError.busy }
        // Retry scratch cleanup if it failed after a prior successful publication.
        try removeInactiveWork()
        let sourceBytes = try regularSize(mediaURL, limit: 500 * 1024 * 1024)
        // Unknown frame bytes use existing capture bounds. Known movie size is
        // used instead of demanding the maximum 1.4GiB for every tiny clip.
        try requireSpace(root(), bytes: 2 * sourceBytes + 3 * Self.captureLimit + 64 * 1024 * 1024)
        try Task.checkCancellation()
        let hash = try BarMediaIdentity.hash(mediaURL), id = UUID()
        let directory = try root().appendingPathComponent(".annotation-work-" + id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let work = AnnotationExportWork(id: id, directory: directory,
            capture: directory.appendingPathComponent("capture", isDirectory: true),
            mediaURL: mediaURL, sourceBytes: sourceBytes, sourceSHA256: hash)
        activeWork = work
        workCleanupFailed = false
        return work
    }
    func abort(_ work: AnnotationExportWork) throws {
        guard activeWork?.id == work.id else { return }
        try owned(work.directory, prefix: ".annotation-work-")
        do {
            try FileManager.default.removeItem(at: work.directory)
            activeWork = nil; workCleanupFailed = false
        } catch { workCleanupFailed = true; throw error }
    }
    func finish(_ work: AnnotationExportWork, context: BarFrameBundleContext,
                authorization: BarCaptureAuthorization) throws -> PreparedAnnotationExport {
        guard activeWork?.id == work.id, prepared == nil, !leased else { throw AnnotationExportError.busy }
        try authorization.check(); try Task.checkCancellation()
        let files = try captureFiles(work, context: context)
        let sourceRecord = AnnotationExportFile(path: context.localPath, bytes: work.sourceBytes, sha256: work.sourceSHA256)
        let records = files + [sourceRecord]
        let total = records.reduce(0) { $0 + $1.bytes }
        guard total < Self.packageLimit - 64 * 1024 else { throw AnnotationExportError.budget }
        try requireSpace(root(), bytes: 2 * total + 64 * 1024 * 1024)
        let staging = work.directory.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: staging.appendingPathComponent("frames"), withIntermediateDirectories: false)
        for record in records {
            let source = record.path == context.localPath ? work.mediaURL : work.capture.appendingPathComponent(record.path)
            try copy(source, to: staging.appendingPathComponent(record.path), record: record, authorization: authorization)
        }
        _ = try BarMediaIdentity.verify(work.mediaURL, expectedSHA256: work.sourceSHA256)
        let receipt = AnnotationExportReceipt(schemaVersion: 1, id: work.id, sourceName: context.localPath,
            sourceSHA256: work.sourceSHA256, sourceBytes: work.sourceBytes, packageBytes: total, files: records)
        let data = try JSONEncoder().encode(receipt)
        guard data.count <= 64 * 1024, total + data.count <= Self.packageLimit else { throw AnnotationExportError.budget }
        try data.write(to: staging.appendingPathComponent("export-receipt.json"), options: .atomic)
        let destination = try root().appendingPathComponent("annotation-" + work.id.uuidString, isDirectory: true)
        try authorization.publish {
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw AnnotationExportError.files }
            try FileManager.default.moveItem(at: staging, to: destination)
        }
        let result = PreparedAnnotationExport(id: work.id, directory: destination,
            sourceBytes: work.sourceBytes, packageBytes: total + data.count)
        prepared = result; activeWork = nil; workCleanupFailed = false
        // Publication is complete. Failure to clean an owned work directory is
        // not allowed to delete a completed package or a user destination.
        try? FileManager.default.removeItem(at: work.directory)
        return result
    }
    func acquirePickerLease(_ id: UUID) throws -> PreparedAnnotationExport {
        try initialize()
        guard let prepared, prepared.id == id, !leased else { throw AnnotationExportError.leased }
        try validatePrepared(prepared.directory)
        try Task.checkCancellation()
        leased = true
        return prepared
    }
    func releasePickerLease(_ id: UUID) { if prepared?.id == id { leased = false } }
    func discard(_ id: UUID? = nil) throws {
        guard !leased else { throw AnnotationExportError.leased }
        if let work = activeWork {
            guard workCleanupFailed else { throw AnnotationExportError.busy }
            try owned(work.directory, prefix: ".annotation-work-")
            try FileManager.default.removeItem(at: work.directory)
            activeWork = nil; workCleanupFailed = false
        }
        if let id, let prepared, id != prepared.id { throw AnnotationExportError.identity }
        try removeInactiveWork()
        // Also allows explicit recovery from an unreadable receipt, but only in
        // this store's owned UUID directory namespace, never user destinations.
        let entries = try FileManager.default.contentsOfDirectory(at: root(), includingPropertiesForKeys: [.isSymbolicLinkKey])
        for entry in entries where entry.lastPathComponent.hasPrefix("annotation-") {
            try owned(entry, prefix: "annotation-")
            try FileManager.default.removeItem(at: entry)
        }
        prepared = nil; initialized = true
    }
    private func regularSize(_ url: URL, limit: Int) throws -> Int {
        let values = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= limit else { throw AnnotationExportError.files }
        return size
    }
    private func data(_ url: URL, limit: Int) throws -> Data {
        _ = try regularSize(url, limit: limit)
        let result = try Data(contentsOf: url)
        guard result.count <= limit else { throw AnnotationExportError.budget }
        return result
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", Int($0)) }.joined() }
    private func object(_ data: Data) throws -> [String: Any] {
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AnnotationExportError.files }
        return result
    }
    private func captureFiles(_ work: AnnotationExportWork, context: BarFrameBundleContext) throws -> [AnnotationExportFile] {
        guard context.localPath == work.mediaURL.lastPathComponent,
              UUID(uuidString: work.mediaURL.deletingPathExtension().lastPathComponent) != nil,
              ["mov", "mp4", "m4v"].contains(work.mediaURL.pathExtension.lowercased()),
              context.prediction.expectedSHA256 == work.sourceSHA256,
              context.assetRoot.standardizedFileURL == work.mediaURL.deletingLastPathComponent().standardizedFileURL else { throw AnnotationExportError.identity }
        let ledgerData = try data(work.capture.appendingPathComponent("ledger.json"), limit: 1024 * 1024)
        let predictionData = try data(work.capture.appendingPathComponent("prediction.json"), limit: 1024 * 1024)
        let bundleData = try data(work.capture.appendingPathComponent("bundle.json"), limit: 48 * 1024 * 1024)
        let ledger = try object(ledgerData), bundle = try object(bundleData)
        guard ledger["schemaVersion"] as? Int == 1, ledger["purpose"] as? String == "native-analysis",
              let clip = ledger["clip"] as? [String: Any], clip["sha256"] as? String == work.sourceSHA256,
              clip["localPath"] as? String == context.localPath, clip["id"] as? String == context.prediction.clipID,
              clip["sourceGroup"] as? String == context.sourceGroup, clip["split"] as? String == "development",
              let association = ledger["association"] as? [String: Any],
              association["predictionSHA256"] as? String == digest(predictionData),
              let frames = ledger["frames"] as? [[String: Any]], (1...16).contains(frames.count),
              let timestamps = association["acceptedTimestamps"] as? [[String: Any]], timestamps.count == frames.count,
              bundle["ledgerText"] as? String == String(data: ledgerData, encoding: .utf8),
              bundle["ledgerSha256"] as? String == digest(ledgerData),
              let embeddedLedger = bundle["ledger"] as? [String: Any], NSDictionary(dictionary: embeddedLedger).isEqual(to: ledger),
              let images = bundle["images"] as? [String: String], images.count == frames.count,
              let width = clip["uprightWidth"] as? Int, let height = clip["uprightHeight"] as? Int else { throw AnnotationExportError.identity }
        var records: [AnnotationExportFile] = [], pngBytes = 0
        for (index, frame) in frames.enumerated() {
            let id = String(format: "frame-%06d", index), name = id + ".png"
            guard frame["id"] as? String == id, frame["filename"] as? String == name,
                  let time = frame["timestamp"] as? [String: Any], NSDictionary(dictionary: time).isEqual(to: timestamps[index]),
                  let hash = frame["sha256"] as? String, let embedded = images[id], embedded.hasPrefix("data:image/png;base64,") else { throw AnnotationExportError.identity }
            let png = try data(work.capture.appendingPathComponent("frames/" + name), limit: 32 * 1024 * 1024)
            let dimensions = try BarFramePNG.dimensions(png)
            guard dimensions.0 == width, dimensions.1 == height, digest(png) == hash,
                  Data(base64Encoded: String(embedded.dropFirst("data:image/png;base64,".count))) == png else { throw AnnotationExportError.identity }
            pngBytes += png.count; guard pngBytes <= 32 * 1024 * 1024 else { throw AnnotationExportError.budget }
            records.append(AnnotationExportFile(path: "frames/" + name, bytes: png.count, sha256: hash))
        }
        for (name, bytes) in [("ledger.json", ledgerData), ("prediction.json", predictionData), ("bundle.json", bundleData)] {
            records.append(AnnotationExportFile(path: name, bytes: bytes.count, sha256: digest(bytes)))
        }
        guard records.reduce(0, { $0 + $1.bytes }) <= Self.captureLimit else { throw AnnotationExportError.budget }
        try exactFiles(work.capture, expected: Set(records.map(\.path)))
        return records
    }
    private func exactFiles(_ directory: URL, expected: Set<String>) throws {
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw AnnotationExportError.files }
        let rootFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])
        var found: Set<String> = []
        for url in rootFiles {
            guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw AnnotationExportError.files }
            if url.lastPathComponent == "frames" {
                for frame in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                    _ = try regularSize(frame, limit: 32 * 1024 * 1024)
                    found.insert("frames/" + frame.lastPathComponent)
                }
            } else {
                _ = try regularSize(url, limit: Self.packageLimit)
                found.insert(url.lastPathComponent)
            }
        }
        guard found == expected else { throw AnnotationExportError.files }
    }
    private func copy(_ source: URL, to destination: URL, record: AnnotationExportFile,
                      authorization: BarCaptureAuthorization) throws {
        guard try regularSize(source, limit: 500 * 1024 * 1024) == record.bytes,
              !FileManager.default.fileExists(atPath: destination.path),
              FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw AnnotationExportError.files }
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: destination)
        defer { try? input.close(); try? output.close() }
        let began = ProcessInfo.processInfo.systemUptime
        var hash = SHA256(), count = 0
        while let bytes = try input.read(upToCount: 128 * 1024), !bytes.isEmpty {
            try Task.checkCancellation(); try authorization.check()
            guard ProcessInfo.processInfo.systemUptime - began < 60, count <= record.bytes - bytes.count else { throw AnnotationExportError.budget }
            try output.write(contentsOf: bytes); hash.update(data: bytes); count += bytes.count
            copyChunkObserver?(source, count)
        }
        try output.synchronize()
        guard count == record.bytes, hash.finalize().map({ String(format: "%02x", Int($0)) }).joined() == record.sha256 else { throw AnnotationExportError.identity }
    }
    private func readReceipt(_ directory: URL) throws -> AnnotationExportReceipt {
        let receiptData = try data(directory.appendingPathComponent("export-receipt.json"), limit: 64 * 1024)
        let receipt = try JSONDecoder().decode(AnnotationExportReceipt.self, from: receiptData)
        guard receipt.schemaVersion == 1, receipt.sourceBytes > 0, receipt.sourceBytes <= 500 * 1024 * 1024,
              receipt.packageBytes > 0, receipt.packageBytes <= Self.packageLimit - receiptData.count,
              (5...20).contains(receipt.files.count), Set(receipt.files.map(\.path)).count == receipt.files.count,
              UUID(uuidString: URL(fileURLWithPath: receipt.sourceName).deletingPathExtension().lastPathComponent) != nil,
              !receipt.sourceName.contains("/"), !receipt.sourceName.contains("\\"),
              ["mov", "mp4", "m4v"].contains(URL(fileURLWithPath: receipt.sourceName).pathExtension.lowercased()) else { throw AnnotationExportError.files }
        for record in receipt.files {
            let frameName = record.path.hasPrefix("frames/frame-") && record.path.hasSuffix(".png") && record.path.count == "frames/frame-000000.png".count &&
                record.path.dropFirst("frames/frame-".count).dropLast(4).utf8.allSatisfy({ (48...57).contains($0) })
            guard record.path == receipt.sourceName || ["ledger.json", "prediction.json", "bundle.json"].contains(record.path) || frameName,
                  !record.path.contains(".."), !record.path.contains("\\"), !record.path.contains(":"),
                  record.bytes > 0, record.bytes <= 500 * 1024 * 1024, record.sha256.count == 64,
                  record.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw AnnotationExportError.files }
        }
        guard receipt.files.reduce(0, { $0 + $1.bytes }) == receipt.packageBytes,
              receipt.files.contains(where: { $0.path == receipt.sourceName && $0.bytes == receipt.sourceBytes && $0.sha256 == receipt.sourceSHA256 }) else { throw AnnotationExportError.files }
        return receipt
    }
    private func validatePrepared(_ directory: URL) throws {
        try owned(directory, prefix: "annotation-")
        let receipt = try readReceipt(directory)
        guard directory.lastPathComponent == "annotation-" + receipt.id.uuidString else { throw AnnotationExportError.identity }
        try exactFiles(directory, expected: Set(receipt.files.map(\.path)).union(["export-receipt.json"]))
        for record in receipt.files {
            let url = directory.appendingPathComponent(record.path)
            guard try regularSize(url, limit: 500 * 1024 * 1024) == record.bytes else { throw AnnotationExportError.identity }
            _ = try BarMediaIdentity.verify(url, expectedSHA256: record.sha256)
        }
    }
}
