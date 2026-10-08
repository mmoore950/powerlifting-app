import Foundation
import CryptoKit
import LiftingCore

/// Explicit developer-provided manifest/revision identity. No defaults fabricate provenance.
struct BarPredictionContext: Sendable {
    let clipID: String
    let expectedSHA256: String
    let modelID: String
    let synthetic: Bool
}
enum BarPredictionError: Error { case unavailable, file, hash, budget }

actor BarPredictionExporter {
    func data(result: BarAnalysisResult, mediaURL: URL, context: BarPredictionContext) throws -> Data {
        guard mediaURL.isFileURL, mediaURL.host?.isEmpty != false else { throw BarPredictionError.file }
        let before = try mediaURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
        let limit = 500 * 1024 * 1024
        guard before.isRegularFile == true, before.contentModificationDate != nil,
              let size = before.fileSize, size > 0, size <= limit else { throw BarPredictionError.file }
        let handle = try FileHandle(forReadingFrom: mediaURL); defer { try? handle.close() }
        let began = ProcessInfo.processInfo.systemUptime
        var hash = SHA256(), count = 0
        while true {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime - began < 60 else { throw BarPredictionError.budget }
            guard let chunk = try handle.read(upToCount: 128 * 1024), !chunk.isEmpty else { break }
            count += chunk.count; guard count <= limit else { throw BarPredictionError.budget }; hash.update(data: chunk)
        }
        let after = try mediaURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let digest = hash.finalize().map { String(format: "%02x", Int($0)) }.joined()
        guard count == size, after.fileSize == size, before.contentModificationDate == after.contentModificationDate,
              digest == context.expectedSHA256 else { throw BarPredictionError.hash }
        let timestamps = try result.timestamps.map { time -> VideoPresentationTime in
            guard let value = Int64(time.value) else { throw VideoPredictionExportError.timestamps }
            return try VideoPresentationTime(value: value, timescale: time.timescale, epoch: time.epoch)
        }
        let run = try VideoPredictionRun(clipID: context.clipID, sha256: digest,
            mode: result.mode == .automatic ? .automatic : .manualVision, synthetic: context.synthetic,
            uprightWidth: result.uprightWidth, uprightHeight: result.uprightHeight, elapsedSeconds: result.elapsed,
            trace: result.trace, timestamps: timestamps)
        try Task.checkCancellation()
        return try VideoPredictionEnvelope(modelID: context.modelID, runs: [run]).jsonData()
    }
}
