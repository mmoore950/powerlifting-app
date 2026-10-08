import XCTest
import AVFoundation
import CryptoKit
import ImageIO
import LiftingCore
@testable import PowerliftingApp

/// Generated media only. These tests require the Apple app host; Node fixtures
/// separately validate the contract and cannot prove this producer executes.
final class BarFrameBundleExporterTests: XCTestCase {
    func testRotatedNativeCaptureMatchesActualRasterAndDefaultNil() async throws {
        try await checkGeneratedCapture(width: 128, height: 96, rotated: true)
    }

    func testWideNativeCaptureUsesActualCappedDimensions() async throws {
        try await checkGeneratedCapture(width: 1280, height: 720, rotated: false)
    }

    func testWriterRejectsIdentityMutationRevocationAndBudgetsWithoutCompletion() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let png = try generatedPNG()
        for scenario in ["run", "session", "timestamp", "source", "image", "revoked", "frames", "bytes", "existing"] {
            let caseRoot = root.appendingPathComponent(scenario, isDirectory: true)
            try FileManager.default.createDirectory(at: caseRoot, withIntermediateDirectories: false)
            let media = caseRoot.appendingPathComponent("synthetic.bin")
            try Data("Generated writer contract bytes, not a movie".utf8).write(to: media)
            let destination = caseRoot.appendingPathComponent("complete", isDirectory: true)
            let authorization = BarCaptureAuthorization()
            let exporter = try BarFrameBundleExporter(mediaURL: media, context: context(media: media),
                destination: destination, authorization: authorization)
            if scenario == "existing" {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                let sentinel = destination.appendingPathComponent("keep.txt")
                try Data("Previous completed destination".utf8).write(to: sentinel)
                do { _ = try await exporter.prepare(); XCTFail("Existing destination accepted") } catch {}
                XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "Previous completed destination")
                continue
            }
            let sink = try await exporter.prepare(), run = UUID()
            let time = BarFrameTime(value: "0", timescale: 30, epoch: 0)
            try await sink.receive(BarCapturedFrame(sessionID: sink.sessionID, analysisID: run,
                timestamp: time, width: 32, height: 24, png: png))
            if scenario == "frames" {
                for index in 1..<16 {
                    try await sink.receive(BarCapturedFrame(sessionID: sink.sessionID, analysisID: run,
                        timestamp: BarFrameTime(value: String(index), timescale: 30, epoch: 0), width: 32, height: 24, png: png))
                }
                do {
                    try await sink.receive(BarCapturedFrame(sessionID: sink.sessionID, analysisID: run,
                        timestamp: BarFrameTime(value: "16", timescale: 30, epoch: 0), width: 32, height: 24, png: png))
                    XCTFail("Seventeenth frame accepted")
                } catch BarFrameBundleError.budget {} catch { XCTFail("Unexpected frame budget error: \(error)") }
            } else if scenario == "bytes" {
                do {
                    try await sink.receive(BarCapturedFrame(sessionID: sink.sessionID, analysisID: run,
                        timestamp: BarFrameTime(value: "1", timescale: 30, epoch: 0), width: 32, height: 24,
                        png: Data(repeating: 0, count: 32 * 1024 * 1024)))
                    XCTFail("PNG byte budget exceeded")
                } catch BarFrameBundleError.budget {} catch { XCTFail("Unexpected byte budget error: \(error)") }
            } else {
                if scenario == "source" { try Data("Changed source".utf8).write(to: media) }
                if scenario == "revoked" { authorization.invalidate() }
                if scenario == "image" {
                    let partial = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: caseRoot, includingPropertiesForKeys: nil)
                        .first { $0.lastPathComponent.hasPrefix(".native-capture-partial-") })
                    try Data("Changed PNG".utf8).write(to: partial.appendingPathComponent("frames/frame-000000.png"))
                }
                let resultTime = scenario == "timestamp" ? BarFrameTime(value: "0", timescale: 60, epoch: 0) : time
                let sample = try VideoTraceSample(seconds: 0, point: nil, confidence: 0, kind: .lost)
                let result = BarAnalysisResult(trace: try VideoTrace(start: 0, end: 0.1, samples: [sample]),
                    timestamps: [resultTime], elapsed: 0.1, gaps: 1, mode: .automatic, uprightWidth: 32, uprightHeight: 24,
                    analysisID: scenario == "run" ? UUID() : run,
                    captureSessionID: scenario == "session" ? UUID() : sink.sessionID)
                do { _ = try await exporter.finish(result: result); XCTFail("Invalid \(scenario) capture completed") } catch {}
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), scenario)
            let partials = try FileManager.default.contentsOfDirectory(at: caseRoot, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix(".native-capture-partial-") }
            XCTAssertEqual(partials.count, 1)
            for partial in partials {
                XCTAssertTrue(FileManager.default.fileExists(atPath: partial.appendingPathComponent("frames/frame-000000.png").path))
                for name in ["ledger.json", "bundle.json", "prediction.json"] {
                    XCTAssertFalse(FileManager.default.fileExists(atPath: partial.appendingPathComponent(name).path), scenario)
                }
            }
        }
    }

    @MainActor
    func testModelRemovalRevokesCaptureBeforeManagedSourceDeletion() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("generated.mov")
        try await SyntheticMovieWriter.write(to: source, width: 128, height: 96, frameCount: 6, timescale: 30, asymmetric: true)
        let model = VideoModel(store: VideoImportStore(rootDirectory: root.appendingPathComponent("managed")))
        await model.importFile(source).value
        let managed = try XCTUnwrap(model.video?.url)
        model.seek(0.1); model.setEnd()
        let destination = root.appendingPathComponent("removed-capture")
        let task = model.captureAnnotationBundle(context: try context(media: managed), destination: destination)
        // No await between starting capture and revoking it on the main actor.
        await model.removeVideo()
        switch await task.result {
        case .success: XCTFail("Removed clip published a capture")
        case .failure: break
        }
        XCTAssertNil(model.video); XCTAssertNil(model.analysisResult); XCTAssertFalse(model.processing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: managed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    private func checkGeneratedCapture(width: Int, height: Int, rotated: Bool) async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appendingPathComponent("generated.mov")
        try await SyntheticMovieWriter.write(to: media, width: width, height: height, frameCount: 6,
            timescale: 30, rotated: rotated, asymmetric: true)
        let analyzer = BarAnalysisService(), destination = root.appendingPathComponent("native")
        let plain = try await analyzer.analyze(url: media, start: 0, end: 0.1, mode: .automatic, manualPoint: nil) { _ in }
        XCTAssertNil(plain.captureSessionID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let exporter = try BarFrameBundleExporter(mediaURL: media, context: context(media: media), destination: destination)
        let sink = try await exporter.prepare()
        let result = try await analyzer.analyze(url: media, start: 0, end: 0.1, mode: .automatic, manualPoint: nil, capture: sink) { _ in }
        let output = try await exporter.finish(result: result)
        XCTAssertEqual(output, destination); XCTAssertEqual(result.captureSessionID, sink.sessionID)
        XCTAssertEqual(result.timestamps.count, plain.timestamps.count)
        XCTAssertGreaterThan(result.timestamps.count, 1)
        XCTAssertLessThanOrEqual(result.timestamps.count, 16)
        XCTAssertLessThanOrEqual(result.uprightWidth, 1024); XCTAssertLessThanOrEqual(result.uprightHeight, 1024)
        if rotated { XCTAssertEqual(result.uprightWidth, height); XCTAssertEqual(result.uprightHeight, width) }
        else { XCTAssertLessThan(result.uprightWidth, width); XCTAssertGreaterThan(result.uprightWidth, result.uprightHeight) }
        let ledger = try object(destination.appendingPathComponent("ledger.json"))
        XCTAssertEqual(ledger["purpose"] as? String, "native-analysis")
        XCTAssertEqual(ledger["nativeParityVerified"] as? Bool, true)
        let frames = try XCTUnwrap(ledger["frames"] as? [[String: Any]])
        let association = try XCTUnwrap(ledger["association"] as? [String: Any])
        XCTAssertEqual(association["analysisID"] as? String, result.analysisID.uuidString)
        XCTAssertEqual(association["captureSessionID"] as? String, sink.sessionID.uuidString)
        let predictionBytes = try Data(contentsOf: destination.appendingPathComponent("prediction.json"))
        XCTAssertEqual(association["predictionSHA256"] as? String, digest(predictionBytes))
        let predictions = try object(destination.appendingPathComponent("prediction.json"))
        let runs = try XCTUnwrap(predictions["runs"] as? [[String: Any]])
        let samples = try XCTUnwrap(runs.first?["samples"] as? [[String: Any]])
        let bundle = try object(destination.appendingPathComponent("bundle.json"))
        let ledgerText = try XCTUnwrap(bundle["ledgerText"] as? String)
        XCTAssertEqual(Data(ledgerText.utf8), try Data(contentsOf: destination.appendingPathComponent("ledger.json")))
        XCTAssertEqual(bundle["ledgerSha256"] as? String, digest(Data(ledgerText.utf8)))
        XCTAssertEqual(frames.count, result.timestamps.count); XCTAssertEqual(samples.count, frames.count)
        let oracle = AVAssetImageGenerator(asset: AVURLAsset(url: media))
        oracle.appliesPreferredTrackTransform = true; oracle.apertureMode = .cleanAperture
        oracle.maximumSize = CGSize(width: 1024, height: 1024)
        oracle.requestedTimeToleranceBefore = .zero; oracle.requestedTimeToleranceAfter = .zero
        defer { oracle.cancelAllCGImageGeneration() }
        for index in frames.indices {
            let timestamp = result.timestamps[index]
            XCTAssertEqual(timestamp.value, plain.timestamps[index].value)
            XCTAssertEqual(timestamp.timescale, plain.timestamps[index].timescale)
            for dictionary in [frames[index], samples[index]] {
                let time = try XCTUnwrap(dictionary["timestamp"] as? [String: Any])
                XCTAssertEqual(time["value"] as? String, timestamp.value)
                XCTAssertEqual(time["timescale"] as? Int, Int(timestamp.timescale))
                XCTAssertEqual(time["epoch"] as? Int, Int(timestamp.epoch))
            }
            let filename = try XCTUnwrap(frames[index]["filename"] as? String)
            let png = try Data(contentsOf: destination.appendingPathComponent("frames").appendingPathComponent(filename))
            XCTAssertEqual(frames[index]["sha256"] as? String, digest(png))
            let pngSource = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(pngSource, 0, nil))
            let actual = try await oracle.image(at: CMTime(value: try XCTUnwrap(Int64(timestamp.value)), timescale: timestamp.timescale))
            XCTAssertEqual(actual.actualTime.value, try XCTUnwrap(Int64(timestamp.value)))
            XCTAssertEqual(actual.actualTime.timescale, timestamp.timescale)
            XCTAssertEqual(image.width, actual.image.width); XCTAssertEqual(image.height, actual.image.height)
            let pixels = try raster(image), expected = try raster(actual.image)
            XCTAssertEqual(pixels.count, expected.count)
            let maximumDifference = zip(pixels, expected).map { abs(Int($0.0)-Int($0.1)) }.max() ?? 0
            XCTAssertLessThanOrEqual(maximumDifference, 2, "PNG/oracle raster mismatch")
            XCTAssertGreaterThan(Int(pixels.max() ?? 0)-Int(pixels.min() ?? 0), 50, "Asymmetric fixture lost contrast")
        }
    }

    private func context(media: URL) throws -> BarFrameBundleContext {
        let hash = digest(try Data(contentsOf: media))
        return BarFrameBundleContext(prediction: BarPredictionContext(clipID: "generated-native-only", expectedSHA256: hash,
            modelID: "generated-capture-test", synthetic: true), assetRoot: media.deletingLastPathComponent(),
            localPath: media.lastPathComponent, sourceGroup: "generated-native-fixture", split: "development",
            permissionEvidence: "Generated synthetic test only", lift: "synthetic", targetID: "near-side-hub")
    }
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private func object(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    private func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", Int($0)) }.joined() }
    private func generatedPNG() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 128,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        return try BarFramePNG.encode(XCTUnwrap(context.makeImage()))
    }
    private func raster(_ image: CGImage) throws -> [UInt8] {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data)
        return Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }
}
