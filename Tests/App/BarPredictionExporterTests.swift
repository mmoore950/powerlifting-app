import XCTest
import CryptoKit
import LiftingCore
@testable import PowerliftingApp

final class BarPredictionExporterTests: XCTestCase {
    func testSyntheticBytesAreHashedAndSchemaKeysRetained() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appendingPathComponent("synthetic.bin"), bytes = Data("synthetic bytes only, not a video".utf8)
        try bytes.write(to: media)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", Int($0)) }.joined()
        let trace = try VideoTrace(start: 0, end: 1, samples: [VideoTraceSample(seconds: 0, point: VideoPoint(x: 0.5,y: 0.5), confidence: 0.8, kind: .automatic, targetID: "track-1")])
        let result = BarAnalysisResult(trace: trace, timestamps: [BarFrameTime(value: "0", timescale: 10, epoch: 0)], elapsed: 1, gaps: 0, mode: .automatic, uprightWidth: 100, uprightHeight: 100)
        let exporter = BarPredictionExporter()
        let context = BarPredictionContext(clipID: "synthetic-only", expectedSHA256: hash, modelID: "synthetic-test-only", synthetic: true)
        let data = try await exporter.data(result: result, mediaURL: media, context: context)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let runs = try XCTUnwrap(object["runs"] as? [[String: Any]])
        XCTAssertEqual(runs[0]["sha256"] as? String, hash); XCTAssertEqual(runs[0]["uprightWidth"] as? Int, 100)
        try Data("changed".utf8).write(to: media)
        do { _ = try await exporter.data(result: result, mediaURL: media, context: context); XCTFail("Changed media accepted") }
        catch BarPredictionError.hash {} catch { XCTFail("Unexpected error: \(error)") }
    }
    func testExplicitManualModeCannotBeRelabeledAsAutomatic() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appendingPathComponent("synthetic.bin"), bytes = Data("synthetic manual fixture".utf8)
        try bytes.write(to: media)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", Int($0)) }.joined()
        let trace = try VideoTrace(start: 0, end: 1, samples: [VideoTraceSample(seconds: 0, point: VideoPoint(x: 0.5,y: 0.5), confidence: 0.8, kind: .tracked, targetID: "manual-vision")])
        let result = BarAnalysisResult(trace: trace, timestamps: [BarFrameTime(value: "0", timescale: 10, epoch: 0)], elapsed: 1, gaps: 0, mode: .manual, uprightWidth: 100, uprightHeight: 100)
        let data = try await BarPredictionExporter().data(result: result, mediaURL: media,
            context: BarPredictionContext(clipID: "synthetic-manual-only", expectedSHA256: hash, modelID: "synthetic-test-only", synthetic: true))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let runs = try XCTUnwrap(object["runs"] as? [[String: Any]])
        XCTAssertEqual(runs[0]["mode"] as? String, "manual-vision")
    }
}
