import Foundation
import CryptoKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import LiftingCore

enum BarFrameBundleError: Error { case context, identity, state, budget, png, timestamp, destination, revoked }

/// Revocation and the final local rename have one linearization point. No await
/// occurs under this lock; image encoding/hashing/writes occur before publication.
final class BarCaptureAuthorization: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    func invalidate() { lock.lock(); active = false; lock.unlock() }
    func check() throws {
        lock.lock(); defer { lock.unlock() }
        guard active else { throw BarFrameBundleError.revoked }
    }
    func publish(_ operation: () throws -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        guard active else { throw BarFrameBundleError.revoked }
        try Task.checkCancellation()
        try operation()
        active = false
    }
}

struct BarCapturedFrame: Sendable {
    let sessionID: UUID, analysisID: UUID
    let timestamp: BarFrameTime
    let width: Int, height: Int
    let png: Data
}
struct BarFrameCaptureSink: Sendable {
    let sessionID: UUID
    let mediaURL: URL
    let receive: @Sendable (BarCapturedFrame) async throws -> Void
}
enum BarFramePNG {
    static func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { throw BarFrameBundleError.png }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw BarFrameBundleError.png }
        return data as Data
    }
    static func dimensions(_ data: Data) throws -> (Int, Int) {
        guard data.prefix(8) == Data([137,80,78,71,13,10,26,10]),
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              (1...1024).contains(width), (1...1024).contains(height),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw BarFrameBundleError.png }
        return (image.width, image.height)
    }
}

struct BarFrameBundleContext: Sendable {
    let prediction: BarPredictionContext
    let assetRoot: URL
    let localPath: String, sourceGroup: String, split: String, permissionEvidence: String, lift: String, targetID: String
}
private struct NativeFrameRecord: Encodable {
    let id: String, filename: String, sha256: String
    let timestamp: BarFrameTime
}
private struct NativeClipRecord: Encodable {
    let id: String, sourceGroup: String, sha256: String, localPath: String, split: String
    let synthetic: Bool
    let permissionEvidence: String, lift: String, targetID: String
    let uprightWidth: Int, uprightHeight: Int
}
private struct NativeFrameAssociation: Encodable {
    let analysisID: String, captureSessionID: String, predictionSHA256: String, modelID: String, mode: String
    let acceptedTimestamps: [BarFrameTime]
    let rangeStart: Double, rangeEnd: Double
}
private struct NativeFrameLedger: Encodable {
    let schemaVersion = 1
    let purpose = "native-analysis"
    let nativeParityVerified = true
    let decoder: [String: String]
    let clip: NativeClipRecord
    let frames: [NativeFrameRecord]
    let association: NativeFrameAssociation
}
private struct NativeFrameBundle: Encodable {
    let ledger: NativeFrameLedger
    let ledgerText: String, ledgerSha256: String
    let images: [String: String]
}

/// One exporter is one analysis session. Partial output deliberately has no ledger
/// until successful publication, and is never reused as a completed destination.
actor BarFrameBundleExporter {
    private enum Phase { case new, capturing, finalizing, completed, failed }
    private var phase = Phase.new
    private let sessionID = UUID()
    private var analysisID: UUID?
    private let mediaURL: URL, destination: URL, staging: URL
    private let context: BarFrameBundleContext
    let authorization: BarCaptureAuthorization
    private var frames: [NativeFrameRecord] = []
    private var images: [String: String] = [:]
    private var frameSizes: [String: Int] = [:]
    private var bytes = 0
    private var dimensions: (Int, Int)?
    private var sourceSize: Int?, sourceModified: Date?

    init(mediaURL: URL, context: BarFrameBundleContext, destination: URL,
         authorization: BarCaptureAuthorization = BarCaptureAuthorization()) throws {
        guard [mediaURL, destination, context.assetRoot].allSatisfy({ $0.isFileURL && $0.host?.isEmpty != false }),
              [context.prediction.clipID, context.sourceGroup, context.permissionEvidence, context.targetID, context.prediction.modelID].allSatisfy({
                  !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.contains("\0") && $0.utf8.count <= 4096
              }), ["training","development","holdout"].contains(context.split),
              ["squat","bench","deadlift","synthetic"].contains(context.lift),
              !context.localPath.isEmpty, !context.localPath.hasPrefix("/"),
              context.localPath.utf8.count <= 4096,
              !context.localPath.contains("\\"), !context.localPath.contains(":"), !context.localPath.contains("\0"),
              !context.localPath.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == ".." || $0 == "." }),
              context.prediction.expectedSHA256.count == 64,
              context.prediction.expectedSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw BarFrameBundleError.context }
        let root = context.assetRoot.standardizedFileURL.resolvingSymlinksInPath()
        let source = mediaURL.standardizedFileURL.resolvingSymlinksInPath()
        guard source.path.hasPrefix(root.path + "/"),
              root.appendingPathComponent(context.localPath).standardizedFileURL.resolvingSymlinksInPath() == source,
              destination.standardizedFileURL != source else { throw BarFrameBundleError.identity }
        self.mediaURL = mediaURL.standardizedFileURL; self.context = context
        self.destination = destination.standardizedFileURL
        staging = destination.deletingLastPathComponent().appendingPathComponent(".native-capture-partial-" + UUID().uuidString, isDirectory: true)
        self.authorization = authorization
    }
    func prepare() throws -> BarFrameCaptureSink {
        do {
            guard case .new = phase else { throw BarFrameBundleError.state }
            try authorization.check(); try Task.checkCancellation()
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw BarFrameBundleError.destination }
            let values = try mediaURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            sourceSize = values.fileSize; sourceModified = values.contentModificationDate
            _ = try BarMediaIdentity.verify(mediaURL, expectedSHA256: context.prediction.expectedSHA256)
            try checkSourceStamp(); try authorization.check(); try Task.checkCancellation()
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: staging.appendingPathComponent("frames"), withIntermediateDirectories: false)
            phase = .capturing
            return BarFrameCaptureSink(sessionID: sessionID, mediaURL: mediaURL) { [self] frame in try await append(frame) }
        } catch { fail(); throw error }
    }
    private func append(_ frame: BarCapturedFrame) throws {
        do {
            guard case .capturing = phase else { throw BarFrameBundleError.state }
            try authorization.check(); try Task.checkCancellation()
            guard frame.sessionID == sessionID, analysisID == nil || analysisID == frame.analysisID else { throw BarFrameBundleError.identity }
            guard frames.count < 16, frame.png.count <= 32 * 1024 * 1024 - bytes else { throw BarFrameBundleError.budget }
            guard (1...1024).contains(frame.width), (1...1024).contains(frame.height), frame.timestamp.epoch == 0,
                  let value = Int64(frame.timestamp.value), value >= 0, frame.timestamp.value == String(value),
                  frame.timestamp.timescale > 0, value <= 1800 * Int64(frame.timestamp.timescale) else { throw BarFrameBundleError.timestamp }
            let time = try VideoPresentationTime(value: value, timescale: frame.timestamp.timescale, epoch: frame.timestamp.epoch)
            if let previous = frames.last {
                guard let prior = Int64(previous.timestamp.value),
                      try VideoPresentationTime(value: prior, timescale: previous.timestamp.timescale, epoch: previous.timestamp.epoch).precedes(time) else { throw BarFrameBundleError.timestamp }
            }
            let actual = try BarFramePNG.dimensions(frame.png)
            guard actual.0 == frame.width, actual.1 == frame.height,
                  dimensions.map({ $0.0 == frame.width && $0.1 == frame.height }) ?? true else { throw BarFrameBundleError.png }
            let id = String(format: "frame-%06d", frames.count), filename = id + ".png"
            try frame.png.write(to: staging.appendingPathComponent("frames").appendingPathComponent(filename), options: .atomic)
            frames.append(NativeFrameRecord(id: id, filename: filename, sha256: Self.digest(frame.png), timestamp: frame.timestamp))
            images[id] = "data:image/png;base64," + frame.png.base64EncodedString()
            frameSizes[id] = frame.png.count
            bytes += frame.png.count; analysisID = frame.analysisID; dimensions = actual
        } catch { fail(); throw error }
    }
    func finish(result: BarAnalysisResult) async throws -> URL {
        do {
            guard case .capturing = phase, !frames.isEmpty, result.captureSessionID == sessionID, result.analysisID == analysisID,
                  result.trace.start >= 0, result.trace.end <= 1800,
                  result.trace.end - result.trace.start <= 1, result.timestamps.count == frames.count,
                  result.trace.samples.count == frames.count, result.uprightWidth == dimensions?.0,
                  result.uprightHeight == dimensions?.1 else { throw BarFrameBundleError.identity }
            try authorization.check(); try Task.checkCancellation(); try checkSourceStamp()
            for index in frames.indices {
                let left = frames[index].timestamp, right = result.timestamps[index]
                guard left.value == right.value, left.timescale == right.timescale, left.epoch == right.epoch else { throw BarFrameBundleError.identity }
            }
            phase = .finalizing
            let predictions = try await BarPredictionExporter().data(result: result, mediaURL: mediaURL, context: context.prediction)
            guard case .finalizing = phase else { throw BarFrameBundleError.state }
            try authorization.check(); try Task.checkCancellation()
            for frame in frames {
                let file = staging.appendingPathComponent("frames").appendingPathComponent(frame.filename)
                let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true, info.fileSize == frameSizes[frame.id] else { throw BarFrameBundleError.png }
                let png = try Data(contentsOf: file)
                let size = try BarFramePNG.dimensions(png)
                guard Self.digest(png) == frame.sha256, size.0 == result.uprightWidth, size.1 == result.uprightHeight else { throw BarFrameBundleError.png }
            }
            let clip = NativeClipRecord(id: context.prediction.clipID, sourceGroup: context.sourceGroup,
                sha256: context.prediction.expectedSHA256, localPath: context.localPath, split: context.split,
                synthetic: context.prediction.synthetic, permissionEvidence: context.permissionEvidence, lift: context.lift,
                targetID: context.targetID, uprightWidth: result.uprightWidth, uprightHeight: result.uprightHeight)
            let association = NativeFrameAssociation(analysisID: result.analysisID.uuidString, captureSessionID: sessionID.uuidString,
                predictionSHA256: Self.digest(predictions), modelID: context.prediction.modelID,
                mode: result.mode == .automatic ? "automatic" : "manual-vision", acceptedTimestamps: result.timestamps,
                rangeStart: result.trace.start, rangeEnd: result.trace.end)
            let ledger = NativeFrameLedger(decoder: ["name":"AVAssetImageGenerator", "version":ProcessInfo.processInfo.operatingSystemVersionString,
                "transform":"preferred-track-transform", "aperture":"clean-aperture", "scale":"maximum-1024x1024",
                "tolerance":"zero", "frameSource":"same-native-analysis"], clip: clip, frames: frames, association: association)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let ledgerData = try encoder.encode(ledger)
            guard let ledgerText = String(data: ledgerData, encoding: .utf8) else { throw BarFrameBundleError.context }
            let bundle = try encoder.encode(NativeFrameBundle(ledger: ledger, ledgerText: ledgerText,
                ledgerSha256: Self.digest(ledgerData), images: images))
            guard bundle.count <= 48 * 1024 * 1024 else { throw BarFrameBundleError.budget }
            try predictions.write(to: staging.appendingPathComponent("prediction.json"), options: .atomic)
            try ledgerData.write(to: staging.appendingPathComponent("ledger.json"), options: .atomic)
            try bundle.write(to: staging.appendingPathComponent("bundle.json"), options: .atomic)
            _ = try BarMediaIdentity.verify(mediaURL, expectedSHA256: context.prediction.expectedSHA256)
            try authorization.publish {
                try checkSourceStamp()
                guard !FileManager.default.fileExists(atPath: destination.path) else { throw BarFrameBundleError.destination }
                try FileManager.default.moveItem(at: staging, to: destination)
            }
            phase = .completed
            return destination
        } catch { fail(); throw error }
    }
    func abort() { fail() }
    private func fail() {
        if case .completed = phase { return }
        phase = .failed; authorization.invalidate()
        // Keep partial PNG diagnostics, but remove authoritative completion files.
        for filename in ["ledger.json","bundle.json","prediction.json"] {
            try? FileManager.default.removeItem(at: staging.appendingPathComponent(filename))
        }
    }
    private func checkSourceStamp() throws {
        let freshURL = URL(fileURLWithPath: mediaURL.path)
        let values = try freshURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let sourceSize, let sourceModified, values.fileSize == sourceSize, values.contentModificationDate == sourceModified else { throw BarFrameBundleError.identity }
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", Int($0)) }.joined() }
}
