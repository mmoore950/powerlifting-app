import XCTest
@testable import LiftingCore

final class VideoPredictionExportTests: XCTestCase {
    private let fixtureSHA256 = String(repeating: "a", count: 64)
    private func trace() throws -> VideoTrace {
        try VideoTrace(start: 0, end: 1, samples: [
            VideoTraceSample(seconds: 0, point: VideoPoint(x: 0.5, y: 0.5), confidence: 0.8, kind: .automatic, targetID: "track-1"),
            VideoTraceSample(seconds: 0.1, point: nil, confidence: 0, kind: .lost)])
    }
    private func run(trace: VideoTrace? = nil, times: [VideoPresentationTime]? = nil, mode: VideoPredictionMode = .automatic,
                     hash: String? = nil, width: Int = 100, elapsed: Double = 1) throws -> VideoPredictionRun {
        try VideoPredictionRun(clipID: "synthetic-only", sha256: hash ?? fixtureSHA256, mode: mode, synthetic: true,
            uprightWidth: width, uprightHeight: 100, elapsedSeconds: elapsed, trace: trace ?? self.trace(),
            timestamps: times ?? [VideoPresentationTime(value: 0, timescale: 10, epoch: 0), VideoPresentationTime(value: 1, timescale: 10, epoch: 0)])
    }
    func testEnvelopeKeepsActualRationalTimesAndExplicitLostNulls() throws {
        let data = try VideoPredictionEnvelope(modelID: "synthetic-test-only", runs: [run()]).jsonData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["coordinateSpace"] as? String, "upright-normalized-top-left")
        let runs = try XCTUnwrap(object["runs"] as? [[String: Any]])
        XCTAssertEqual(runs[0]["synthetic"] as? Bool, true)
        let samples = try XCTUnwrap(runs[0]["samples"] as? [[String: Any]])
        XCTAssertEqual((samples[1]["timestamp"] as? [String: Any])?["value"] as? String, "1")
        XCTAssertTrue(samples[1]["point"] is NSNull); XCTAssertTrue(samples[1]["targetID"] is NSNull)
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "video-prediction-synthetic", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? NSDictionary)
        XCTAssertEqual(object as NSDictionary, fixture)
        let wide = try VideoPresentationTime(value: 9_007_199_254_740_993, timescale: 600, epoch: 0)
        let timeObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(wide)) as? [String: Any])
        XCTAssertEqual(timeObject["value"] as? String, "9007199254740993")
    }
    func testRationalOrderAvoidsInt64OverflowAndRejectsDuplicateScales() throws {
        let a = try VideoPresentationTime(value: Int64.max-1, timescale: Int32.max, epoch: 0)
        let b = try VideoPresentationTime(value: Int64.max, timescale: Int32.max, epoch: 0)
        XCTAssertTrue(a.precedes(b)); XCTAssertFalse(b.precedes(a))
        let negative = try VideoPresentationTime(value: Int64.min, timescale: Int32.max, epoch: 0)
        XCTAssertTrue(negative.precedes(a))
        let equivalentA = try VideoPresentationTime(value: 1, timescale: 10, epoch: 0)
        let equivalentB = try VideoPresentationTime(value: 2, timescale: 20, epoch: 0)
        XCTAssertFalse(equivalentA.precedes(equivalentB))
        XCTAssertThrowsError(try run(times: [equivalentA,equivalentB]))
        XCTAssertThrowsError(try VideoPresentationTime(value: 0, timescale: 0, epoch: 0))
        XCTAssertThrowsError(try VideoPresentationTime(value: 0, timescale: 10, epoch: 9_007_199_254_740_992))
    }
    func testPairingModeManualReferencesAndMissingIdentityFail() throws {
        XCTAssertThrowsError(try run(times: []))
        XCTAssertThrowsError(try run(times: [VideoPresentationTime(value: 0, timescale: 10, epoch: 0), VideoPresentationTime(value: 2, timescale: 10, epoch: 0)]))
        XCTAssertThrowsError(try run(mode: .manualVision))
        let manual = try VideoTrace(start: 0, end: 1, samples: [VideoTraceSample(seconds: 0, point: VideoPoint(x: 0.5,y: 0.5), confidence: 1, kind: .manualReference)])
        XCTAssertThrowsError(try run(trace: manual, times: [VideoPresentationTime(value: 0, timescale: 10, epoch: 0)]))
        let unidentified = try VideoTrace(start: 0, end: 1, samples: [VideoTraceSample(seconds: 0, point: VideoPoint(x: 0.5,y: 0.5), confidence: 1, kind: .tracked)])
        XCTAssertThrowsError(try run(trace: unidentified, times: [VideoPresentationTime(value: 0, timescale: 10, epoch: 0)]))
    }
    func testExplicitMetadataAndUniqueClipModeRequired() throws {
        XCTAssertThrowsError(try run(hash: "unknown")); XCTAssertThrowsError(try run(width: 0)); XCTAssertThrowsError(try run(elapsed: .nan))
        XCTAssertThrowsError(try VideoPredictionEnvelope(modelID: "", runs: []))
        XCTAssertThrowsError(try VideoPredictionEnvelope(modelID: "synthetic-test-only", runs: [run(),run()]))
    }
}
