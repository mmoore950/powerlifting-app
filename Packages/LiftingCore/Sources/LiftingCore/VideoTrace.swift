import Foundation

public enum VideoTraceError: Error { case invalidGeometry, invalidSample, invalidRange }

/// Canonical coordinates: upright displayed image, normalized, origin at top left.
public struct VideoPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) throws {
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
            throw VideoTraceError.invalidGeometry
        }
        self.x = x; self.y = y
    }
    public init(visionX: Double, visionY: Double) throws { try self.init(x: visionX, y: 1 - visionY) }
    enum CodingKeys: String, CodingKey { case x, y }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(x: values.decode(Double.self, forKey: .x), y: values.decode(Double.self, forKey: .y))
    }
}

public struct VideoFit: Sendable {
    public let x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) throws {
        guard [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else {
            throw VideoTraceError.invalidGeometry
        }
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public init(imageWidth: Double, imageHeight: Double, containerWidth: Double, containerHeight: Double) throws {
        guard [imageWidth, imageHeight, containerWidth, containerHeight].allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw VideoTraceError.invalidGeometry
        }
        let scale = min(containerWidth / imageWidth, containerHeight / imageHeight)
        try self.init(x: (containerWidth - imageWidth * scale) / 2,
            y: (containerHeight - imageHeight * scale) / 2, width: imageWidth * scale, height: imageHeight * scale)
    }
    public func imagePoint(screenX: Double, screenY: Double) -> VideoPoint? {
        try? VideoPoint(x: (screenX - x) / width, y: (screenY - y) / height)
    }
    public func screenPoint(_ point: VideoPoint) -> (x: Double, y: Double) {
        (x + point.x * width, y + point.y * height)
    }
}

/// Applies AVFoundation's preferred affine transform, including translation/mirroring.
public struct VideoOrientation: Sendable {
    public let a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double
    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public func upright(rawX: Double, rawY: Double, width: Double, height: Double) throws -> VideoPoint {
        guard [a,b,c,d,tx,ty,width,height,rawX,rawY].allSatisfy(\.isFinite), width > 0, height > 0,
              (0...width).contains(rawX), (0...height).contains(rawY) else { throw VideoTraceError.invalidGeometry }
        guard abs(a * d - b * c) > 1e-12 else { throw VideoTraceError.invalidGeometry }
        let corners = [(0.0,0.0),(width,0.0),(0.0,height),(width,height)].map {
            (x: a * $0.0 + c * $0.1 + tx, y: b * $0.0 + d * $0.1 + ty)
        }
        let minX = corners.map(\.x).min()!, maxX = corners.map(\.x).max()!
        let minY = corners.map(\.y).min()!, maxY = corners.map(\.y).max()!
        guard maxX > minX, maxY > minY else { throw VideoTraceError.invalidGeometry }
        return try VideoPoint(x: (a * rawX + c * rawY + tx - minX) / (maxX - minX),
                              y: (b * rawX + d * rawY + ty - minY) / (maxY - minY))
    }
}

public struct VideoTraceSample: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case automatic, tracked, manualReference, lost }
    public let seconds: Double
    public let point: VideoPoint?
    public let confidence: Double
    public let kind: Kind
    public let targetID: String?
    public init(seconds: Double, point: VideoPoint?, confidence: Double, kind: Kind, targetID: String? = nil) throws {
        guard seconds.isFinite, seconds >= 0, confidence.isFinite, (0...1).contains(confidence),
              (kind == .lost) == (point == nil) else { throw VideoTraceError.invalidSample }
        if let targetID, targetID.isEmpty || targetID.count > 128 || targetID.contains("\0") { throw VideoTraceError.invalidSample }
        self.seconds = seconds; self.point = point; self.confidence = confidence; self.kind = kind
        self.targetID = targetID
    }
    enum CodingKeys: String, CodingKey { case seconds, point, confidence, kind, targetID }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(seconds: values.decode(Double.self, forKey: .seconds),
            point: values.decodeIfPresent(VideoPoint.self, forKey: .point),
            confidence: values.decode(Double.self, forKey: .confidence), kind: values.decode(Kind.self, forKey: .kind),
            targetID: values.decodeIfPresent(String.self, forKey: .targetID))
    }
}

public struct VideoTrace: Codable, Sendable {
    public let start: Double
    public let end: Double
    public let samples: [VideoTraceSample]
    public init(start: Double, end: Double, samples: [VideoTraceSample]) throws {
        guard start.isFinite, end.isFinite, start >= 0, end > start, end - start <= 30,
              samples.count <= 10_000 else { throw VideoTraceError.invalidRange }
        var previous = -Double.infinity
        for sample in samples {
            guard sample.seconds >= start, sample.seconds <= end, sample.seconds > previous else {
                throw VideoTraceError.invalidSample
            }
            previous = sample.seconds
        }
        self.start = start; self.end = end; self.samples = samples
    }
    public func segments(through seconds: Double, minimumConfidence: Double = 0.5,
                         maximumGap: Double = 0.2) -> [[VideoPoint]] {
        guard seconds.isFinite, minimumConfidence.isFinite, (0...1).contains(minimumConfidence),
              maximumGap.isFinite, maximumGap > 0 else { return [] }
        var result: [[VideoPoint]] = [], segment: [VideoPoint] = [], previous: Double?, previousTarget: String?
        for sample in samples where sample.seconds <= seconds {
            guard let point = sample.point, sample.confidence >= minimumConfidence else {
                if !segment.isEmpty { result.append(segment) }; segment = []; previous = nil; previousTarget = nil; continue
            }
            if let previous, sample.seconds - previous > maximumGap || previousTarget != sample.targetID {
                if !segment.isEmpty { result.append(segment) }; segment = []
            }
            segment.append(point); previous = sample.seconds; previousTarget = sample.targetID
        }
        if !segment.isEmpty { result.append(segment) }
        return result
    }
    enum CodingKeys: String, CodingKey { case start, end, samples }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(start: values.decode(Double.self, forKey: .start), end: values.decode(Double.self, forKey: .end),
                      samples: values.decode([VideoTraceSample].self, forKey: .samples))
    }
}
