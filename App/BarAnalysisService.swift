import Foundation
import AVFoundation
import Vision
import CoreGraphics
import LiftingCore

enum BarAnalysisMode: String, CaseIterable, Sendable { case automatic = "Experimental automatic", manual = "Manual Vision" }
struct BarAnalysisProgress: Sendable {
    let fraction: Double
    let frames: Int
    let reason: String
}
struct BarFrameTime: Codable, Sendable {
    let value: String
    let timescale: Int32
    let epoch: Int64
}
struct BarAnalysisResult: Sendable {
    let trace: VideoTrace
    let timestamps: [BarFrameTime]
    let elapsed: Double
    let gaps: Int
    let mode: BarAnalysisMode
    let uprightWidth: Int
    let uprightHeight: Int
    let analysisID: UUID
    let captureSessionID: UUID?
    init(trace: VideoTrace, timestamps: [BarFrameTime], elapsed: Double, gaps: Int, mode: BarAnalysisMode,
         uprightWidth: Int, uprightHeight: Int, analysisID: UUID = UUID(), captureSessionID: UUID? = nil) {
        self.trace = trace; self.timestamps = timestamps; self.elapsed = elapsed; self.gaps = gaps; self.mode = mode
        self.uprightWidth = uprightWidth; self.uprightHeight = uprightHeight
        self.analysisID = analysisID; self.captureSessionID = captureSessionID
    }
}
enum BarAnalysisError: Error, LocalizedError {
    case busy, range, manualPoint, timestamp, budget, noFrames, geometry
    var errorDescription: String? {
        switch self {
        case .busy: return "Previous processing is still cleaning up."
        case .range: return "Select a rep no longer than 30 seconds."
        case .manualPoint: return "Manual Vision needs a reference point at the start of the selected rep."
        case .timestamp: return "The video returned unsupported presentation timestamps."
        case .budget: return "Processing reached its frame or elapsed budget. Try a shorter rep."
        case .noFrames: return "No usable frames were decoded in this range."
        case .geometry: return "The upright image dimensions changed during decoding. Choose another clip."
        }
    }
}

actor BarAnalysisService {
    /// Maintained implementation identifier, not a Git revision or accuracy claim.
    static let implementationID = "native-bar-analysis-v1"
    private var running = false
    func analyze(url: URL, start: Double, end: Double, mode: BarAnalysisMode, manualPoint: VideoPoint?,
                 capture: BarFrameCaptureSink? = nil,
                 progress: @escaping @Sendable (BarAnalysisProgress) -> Void) async throws -> BarAnalysisResult {
        guard !running else { throw BarAnalysisError.busy }
        guard start.isFinite, end.isFinite, start >= 0, end > start, end - start <= 30 else { throw BarAnalysisError.range }
        if mode == .manual && manualPoint == nil { throw BarAnalysisError.manualPoint }
        if let capture {
            guard end - start <= 1, url.standardizedFileURL == capture.mediaURL.standardizedFileURL else { throw BarFrameBundleError.identity }
        }
        let analysisID = UUID()
        running = true; defer { running = false }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.apertureMode = .cleanAperture
        generator.maximumSize = CGSize(width: 1024, height: 1024)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let began = ProcessInfo.processInfo.systemUptime
        let cancellation = VisionCancellation(generator: generator)
        var samples: [VideoTraceSample] = [], timestamps: [BarFrameTime] = []
        var uprightWidth: Int?, uprightHeight: Int?
        var clock = try VideoSampleClock(start: start, end: end)
        var machine = BarCandidateTracker(), previousFeatures: [ContourLandmark] = []
        let sequence = VNSequenceRequestHandler()
        var manualRequest: VNTrackObjectRequest?
        var manualLost = false, gaps = 0
        defer { generator.cancelAllCGImageGeneration(); manualRequest?.cancel() }
        return try await withTaskCancellationHandler {
            for index in 0..<clock.requestCount {
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.systemUptime - began < 120 else { throw BarAnalysisError.budget }
                let requested = try clock.requestedSeconds(index: index)
                let frame = try await generator.image(at: CMTime(seconds: requested, preferredTimescale: 60_000))
                try Task.checkCancellation()
                guard frame.actualTime.isNumeric else { throw BarAnalysisError.timestamp }
                if let uprightWidth, let uprightHeight {
                    guard frame.image.width == uprightWidth, frame.image.height == uprightHeight else { throw BarAnalysisError.geometry }
                } else { uprightWidth = frame.image.width; uprightHeight = frame.image.height }
                guard let actual = try clock.accept(value: frame.actualTime.value, timescale: frame.actualTime.timescale,
                    epoch: frame.actualTime.epoch) else { continue }
                if let capture {
                    let png = try autoreleasepool { try BarFramePNG.encode(frame.image) }
                    try Task.checkCancellation()
                    try await capture.receive(BarCapturedFrame(sessionID: capture.sessionID, analysisID: analysisID,
                        timestamp: BarFrameTime(value: String(frame.actualTime.value), timescale: frame.actualTime.timescale, epoch: frame.actualTime.epoch),
                        width: frame.image.width, height: frame.image.height, png: png))
                    try Task.checkCancellation()
                }
                let observation: (VideoTraceSample, String) = try autoreleasepool {
                    if mode == .automatic {
                        let features = try ContourFrame.extract(frame.image, cancellation: cancellation)
                        let shift = ContourFrame.sceneShift(previous: previousFeatures, current: features.landmarks)
                        previousFeatures = features.landmarks
                        let decision = try machine.process(seconds: actual, candidates: features.candidates, scene: shift)
                        return (try VideoTraceSample(seconds: actual, point: decision.point, confidence: decision.score,
                            kind: decision.kind, targetID: decision.targetID), decision.reason)
                    }
                    if manualRequest == nil, let manualPoint {
                        let width = 0.08, height = min(0.3, width * Double(frame.image.width) / Double(frame.image.height))
                        let box = CGRect(x: min(1-width,max(0,manualPoint.x-width/2)),
                            y: min(1-height,max(0,1-manualPoint.y-height/2)), width: width, height: height)
                        manualRequest = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: box))
                        manualRequest?.trackingLevel = .accurate
                    }
                    guard let request = manualRequest, !manualLost else {
                        return (try VideoTraceSample(seconds: actual, point: nil, confidence: 0, kind: .lost), "Manual target lost; reinitialize explicitly")
                    }
                    cancellation.begin(request)
                    defer { cancellation.end(request) }
                    try sequence.perform([request], on: frame.image, orientation: .up)
                    guard let found = request.results?.first as? VNDetectedObjectObservation, found.confidence >= 0.6,
                          found.confidence <= 1, !found.boundingBox.isEmpty,
                          let point = try? VideoPoint(visionX: Double(found.boundingBox.midX), visionY: Double(found.boundingBox.midY)) else {
                        manualLost = true
                        return (try VideoTraceSample(seconds: actual, point: nil, confidence: 0, kind: .lost), "Manual Vision lost confidence")
                    }
                    request.inputObservation = found
                    return (try VideoTraceSample(seconds: actual, point: point, confidence: Double(found.confidence),
                        kind: .tracked, targetID: "manual-vision"), "Manual Vision score; semantic target chosen by user")
                }
                try Task.checkCancellation()
                samples.append(observation.0)
                timestamps.append(BarFrameTime(value: String(frame.actualTime.value), timescale: frame.actualTime.timescale, epoch: frame.actualTime.epoch))
                if observation.0.point == nil { gaps += 1 }
                progress(BarAnalysisProgress(fraction: min(1,(actual-start)/(end-start)), frames: samples.count, reason: observation.1))
            }
            guard !samples.isEmpty, let uprightWidth, let uprightHeight else { throw BarAnalysisError.noFrames }
            return BarAnalysisResult(trace: try VideoTrace(start: start, end: end, samples: samples), timestamps: timestamps,
                elapsed: ProcessInfo.processInfo.systemUptime - began, gaps: gaps, mode: mode,
                uprightWidth: uprightWidth, uprightHeight: uprightHeight, analysisID: analysisID, captureSessionID: capture?.sessionID)
        } onCancel: { cancellation.cancel() }
    }
}

/// Apple cancellation APIs may be called while an operation is in flight.
/// Lock protects cross-thread request ownership; images/state remain actor-confined.
final class VisionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private let generator: AVAssetImageGenerator
    private var current: VNRequest?
    private var cancelled = false
    init(generator: AVAssetImageGenerator) { self.generator = generator }
    func begin(_ request: VNRequest) {
        lock.lock(); current = request; let shouldCancel = cancelled; lock.unlock()
        if shouldCancel { request.cancel() }
    }
    func end(_ request: VNRequest) {
        lock.lock(); if current === request { current = nil }; lock.unlock()
    }
    func cancel() {
        lock.lock(); cancelled = true; let request = current; lock.unlock()
        generator.cancelAllCGImageGeneration(); request?.cancel()
    }
}
