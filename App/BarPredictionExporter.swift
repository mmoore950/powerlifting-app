import Foundation
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
        let digest = try BarMediaIdentity.verify(mediaURL, expectedSHA256: context.expectedSHA256)
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
