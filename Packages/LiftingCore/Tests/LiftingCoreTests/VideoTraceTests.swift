import XCTest
@testable import LiftingCore

final class VideoTraceTests: XCTestCase {
    func testLetterboxAndPortraitRoundTripsRejectBlackBars() throws {
        let landscape = try VideoFit(imageWidth: 1920, imageHeight: 1080, containerWidth: 300, containerHeight: 300)
        XCTAssertEqual(landscape.y, 65.625, accuracy: 0.0001)
        XCTAssertNil(landscape.imagePoint(screenX: 150, screenY: 20))
        let center = try VideoPoint(x: 0.5, y: 0.5), screen = landscape.screenPoint(center)
        XCTAssertEqual(landscape.imagePoint(screenX: screen.x, screenY: screen.y), center)
        let portrait = try VideoFit(imageWidth: 1080, imageHeight: 1920, containerWidth: 300, containerHeight: 300)
        XCTAssertEqual(portrait.x, 65.625, accuracy: 0.0001)
        XCTAssertNil(portrait.imagePoint(screenX: 20, screenY: 150))
    }
    func testRotationTranslationMirroringAndVisionOrigin() throws {
        let clockwise = VideoOrientation(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        XCTAssertEqual(try clockwise.upright(rawX: 0, rawY: 0, width: 1920, height: 1080), try VideoPoint(x: 1, y: 0))
        XCTAssertEqual(try clockwise.upright(rawX: 960, rawY: 540, width: 1920, height: 1080), try VideoPoint(x: 0.5, y: 0.5))
        let mirror = VideoOrientation(a: -1, b: 0, c: 0, d: 1, tx: 1920, ty: 0)
        XCTAssertEqual(try mirror.upright(rawX: 0, rawY: 1080, width: 1920, height: 1080), try VideoPoint(x: 1, y: 1))
        XCTAssertEqual(try VideoPoint(visionX: 0.25, visionY: 0.75), try VideoPoint(x: 0.25, y: 0.25))
    }
    func testNoPathBridgeAcrossLostLowConfidenceOrTimestampGaps() throws {
        let point = try VideoPoint(x: 0.5, y: 0.5)
        let samples = try [
            VideoTraceSample(seconds: 1, point: point, confidence: 1, kind: .tracked),
            VideoTraceSample(seconds: 1.05, point: point, confidence: 1, kind: .tracked),
            VideoTraceSample(seconds: 1.1, point: nil, confidence: 0, kind: .lost),
            VideoTraceSample(seconds: 1.15, point: point, confidence: 1, kind: .tracked),
            VideoTraceSample(seconds: 1.2, point: point, confidence: 0.1, kind: .tracked),
            VideoTraceSample(seconds: 1.25, point: point, confidence: 1, kind: .tracked),
            VideoTraceSample(seconds: 2, point: point, confidence: 1, kind: .manualReference)]
        let trace = try VideoTrace(start: 1, end: 3, samples: samples)
        XCTAssertEqual(trace.segments(through: 3).map(\.count), [2,1,1,1])
        XCTAssertEqual(trace.segments(through: 1.05).map(\.count), [2])
        XCTAssertTrue(trace.segments(through: .nan).isEmpty)
        let decoded = try JSONDecoder().decode(VideoTrace.self, from: JSONEncoder().encode(trace))
        XCTAssertEqual(decoded.samples.count, samples.count)
    }
    func testInvalidRangesUnorderedSamplesAndMalformedDecoding() throws {
        let point = try VideoPoint(x: 0.5, y: 0.5)
        XCTAssertThrowsError(try VideoPoint(x: .nan, y: 0))
        XCTAssertThrowsError(try VideoTraceSample(seconds: 0, point: point, confidence: 1, kind: .lost))
        let sample = try VideoTraceSample(seconds: 1, point: point, confidence: 1, kind: .manualReference)
        XCTAssertThrowsError(try VideoTrace(start: 0, end: 31, samples: []))
        XCTAssertThrowsError(try VideoTrace(start: 0, end: 2, samples: [sample,sample]))
        XCTAssertThrowsError(try JSONDecoder().decode(VideoPoint.self, from: Data("{\"x\":2,\"y\":0}".utf8)))
    }
}
