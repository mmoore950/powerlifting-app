import Foundation

public enum VideoPredictionExportError: Error {
    case metadata, samples, timestamps, duplicateRun
}

/// Stores the decoder's original rational PTS; never reconstructed from trace Double seconds.
public struct VideoPresentationTime: Encodable, Sendable {
    public let value: Int64
    public let timescale: Int32
    public let epoch: Int64
    public init(value: Int64, timescale: Int32, epoch: Int64) throws {
        guard timescale > 0, epoch >= 0, epoch <= 9_007_199_254_740_991 else { throw VideoPredictionExportError.timestamps }
        self.value = value; self.timescale = timescale; self.epoch = epoch
    }
    public var seconds: Double { Double(value) / Double(timescale) }
    public func precedes(_ other: Self) -> Bool {
        if epoch != other.epoch { return epoch < other.epoch }
        let left = value.multipliedFullWidth(by: Int64(other.timescale))
        let right = other.value.multipliedFullWidth(by: Int64(timescale))
        return left.high < right.high || (left.high == right.high && left.low < right.low)
    }
    enum CodingKeys: String, CodingKey { case value, timescale, epoch }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(String(value), forKey: .value)
        try values.encode(timescale, forKey: .timescale); try values.encode(epoch, forKey: .epoch)
    }
}

public enum VideoPredictionMode: String, Encodable, Sendable { case automatic, manualVision = "manual-vision" }

public struct VideoPredictionSample: Encodable, Sendable {
    public let timestamp: VideoPresentationTime
    public let point: VideoPoint?
    public let confidence: Double
    public let kind: VideoTraceSample.Kind
    public let targetID: String?
    fileprivate init(sample: VideoTraceSample, timestamp: VideoPresentationTime, mode: VideoPredictionMode) throws {
        guard timestamp.epoch == 0, timestamp.seconds == sample.seconds,
              sample.kind != .manualReference, mode != .manualVision || sample.kind != .automatic,
              sample.point == nil || sample.targetID != nil else { throw VideoPredictionExportError.samples }
        if let targetID = sample.targetID {
            guard !targetID.isEmpty, targetID.unicodeScalars.count <= 128, !targetID.contains("\0") else { throw VideoPredictionExportError.samples }
        }
        self.timestamp = timestamp; point = sample.point; confidence = sample.confidence; kind = sample.kind; targetID = sample.targetID
    }
    enum CodingKeys: String, CodingKey { case timestamp, point, confidence, kind, targetID }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(timestamp, forKey: .timestamp); try values.encode(point, forKey: .point)
        try values.encode(confidence, forKey: .confidence); try values.encode(kind, forKey: .kind)
        // Explicit null keys are required by the prediction schema, including lost samples.
        try values.encode(targetID, forKey: .targetID)
    }
}

public struct VideoPredictionRun: Encodable, Sendable {
    public let clipID: String, sha256: String
    public let mode: VideoPredictionMode
    public let synthetic: Bool
    public let uprightWidth: Int, uprightHeight: Int
    public let elapsedSeconds: Double
    public let samples: [VideoPredictionSample]
    public init(clipID: String, sha256: String, mode: VideoPredictionMode, synthetic: Bool,
                uprightWidth: Int, uprightHeight: Int, elapsedSeconds: Double,
                trace: VideoTrace, timestamps: [VideoPresentationTime]) throws {
        guard !clipID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !clipID.contains("\0"),
              sha256.count == 64, sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              (1...8192).contains(uprightWidth), (1...8192).contains(uprightHeight),
              elapsedSeconds.isFinite, elapsedSeconds >= 0, trace.end <= 1800 else { throw VideoPredictionExportError.metadata }
        guard !trace.samples.isEmpty, trace.samples.count <= 450, trace.samples.count == timestamps.count else { throw VideoPredictionExportError.samples }
        for index in timestamps.indices {
            if index > 0, !timestamps[index-1].precedes(timestamps[index]) { throw VideoPredictionExportError.timestamps }
        }
        self.clipID = clipID; self.sha256 = sha256; self.mode = mode; self.synthetic = synthetic
        self.uprightWidth = uprightWidth; self.uprightHeight = uprightHeight; self.elapsedSeconds = elapsedSeconds
        samples = try zip(trace.samples, timestamps).map { try VideoPredictionSample(sample: $0.0, timestamp: $0.1, mode: mode) }
    }
}

public struct VideoPredictionEnvelope: Encodable, Sendable {
    public let schemaVersion = 1
    public let coordinateSpace = "upright-normalized-top-left"
    public let modelID: String
    public let runs: [VideoPredictionRun]
    public init(modelID: String, runs: [VideoPredictionRun]) throws {
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, modelID.unicodeScalars.count <= 200, !modelID.contains("\0"), runs.count <= 200 else { throw VideoPredictionExportError.metadata }
        var keys = Set<String>()
        for run in runs {
            let key = run.clipID + "\0" + run.mode.rawValue
            guard keys.insert(key).inserted else { throw VideoPredictionExportError.duplicateRun }
        }
        self.modelID = modelID; self.runs = runs
    }
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }
}
