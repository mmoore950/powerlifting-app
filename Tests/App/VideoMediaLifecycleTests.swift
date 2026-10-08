import XCTest
import AVFoundation
import CoreVideo
@testable import PowerliftingApp

final class VideoMediaLifecycleTests: XCTestCase {
    @MainActor
    func testGeneratedMovieImportsWithUprightMetadataAndDecodes() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mov")
        try await SyntheticMovieWriter.write(to: source)
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let store = VideoImportStore(rootDirectory: managed)
        let imported = try await store.ingest(source)
        XCTAssertEqual(imported.url.deletingLastPathComponent(), managed)
        XCTAssertNotEqual(imported.url, source)
        XCTAssertEqual(imported.duration, 0.3, accuracy: 0.02)
        XCTAssertEqual(imported.width, 48, accuracy: 0.001)
        XCTAssertEqual(imported.height, 64, accuracy: 0.001)
        XCTAssertEqual(try Data(contentsOf: imported.url), try Data(contentsOf: source))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: imported.url))
        generator.appliesPreferredTrackTransform = true
        let frame = try await generator.image(at: .zero)
        XCTAssertEqual(frame.image.width, 48)
        XCTAssertEqual(frame.image.height, 64)
        try await store.remove(imported.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imported.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testInvalidMediaLeavesNoManagedCopyAndKeepsSource() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("invalid.mov")
        let bytes = Data("Synthetic invalid media, not a movie".utf8)
        try bytes.write(to: source)
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let store = VideoImportStore(rootDirectory: managed)
        do { _ = try await store.ingest(source); XCTFail("Invalid movie accepted") }
        catch { XCTAssertFalse(error is CancellationError) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: managed.path), [])
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    func testRemovalRefusesSourceAndClearPreservesUnmanagedFile() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mov")
        try await SyntheticMovieWriter.write(to: source)
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let store = VideoImportStore(rootDirectory: managed)
        let imported = try await store.ingest(source)
        do { try await store.remove(source); XCTFail("Source removal accepted") }
        catch VideoImportError.unsupported {} catch { XCTFail("Unexpected refusal: \(error)") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.url.path))
        let sentinel = managed.appendingPathComponent("unmanaged.txt")
        try Data("owned test sentinel".utf8).write(to: sentinel)
        try await store.clearManagedCopies()
        XCTAssertFalse(FileManager.default.fileExists(atPath: imported.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
    }

    @MainActor
    func testModelReplacementDetachesPlayersAndFailedImportPreservesCurrentVideo() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.mov")
        let second = root.appendingPathComponent("second.mov")
        try await SyntheticMovieWriter.write(to: first)
        try FileManager.default.copyItem(at: first, to: second)
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let model = VideoModel(store: VideoImportStore(rootDirectory: managed))
        await model.importFile(first).value
        XCTAssertNil(model.error)
        let firstCopy = try XCTUnwrap(model.video?.url)
        let firstPlayer = try XCTUnwrap(model.player)
        XCTAssertNotNil(firstPlayer.currentItem)

        let invalid = root.appendingPathComponent("invalid.mov")
        try Data("Synthetic invalid replacement".utf8).write(to: invalid)
        await model.importFile(invalid).value
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.video?.url, firstCopy)
        XCTAssertTrue(model.player === firstPlayer)
        XCTAssertNotNil(firstPlayer.currentItem)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: managed.path).count, 1)

        await model.importFile(second).value
        XCTAssertNil(model.error)
        XCTAssertFalse(model.importing)
        let secondCopy = try XCTUnwrap(model.video?.url)
        let secondPlayer = try XCTUnwrap(model.player)
        XCTAssertNotEqual(firstCopy, secondCopy)
        XCTAssertNil(firstPlayer.currentItem)
        XCTAssertNotNil(secondPlayer.currentItem)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstCopy.path))
        await model.removeVideo()
        XCTAssertNil(secondPlayer.currentItem)
        XCTAssertNil(model.player); XCTAssertNil(model.video)
        XCTAssertNil(model.trace); XCTAssertNil(model.analysisResult)
        XCTAssertFalse(model.playing); XCTAssertEqual(model.seconds, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: managed.path), [])
        for source in [first, second, invalid] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        }
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("media-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}

/// Test-only encoder. Mutable state and writer operations are confined to one serial queue.
/// The unchecked conformance permits AVFoundation callbacks to retain this queue-owned state;
/// no mutable field is accessed from the calling task or the writer completion queue.
final class SyntheticMovieWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "synthetic-movie-writer")
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let destination: URL
    private let width: Int, height: Int, frameCount: Int
    private let timescale: Int32
    private let asymmetric: Bool
    private var nextFrame = 0
    private var completed = false
    private var completion: (@Sendable (Result<Void, Error>) -> Void)?
    private var deadline: DispatchWorkItem?
    private var phase = "not started"
    private var startedAt = 0.0

    static func write(to url: URL, width: Int = 64, height: Int = 48, frameCount: Int = 3,
                      timescale: Int32 = 10, rotated: Bool = true, asymmetric: Bool = false) async throws {
        let encoder = try SyntheticMovieWriter(destination: url, width: width, height: height,
            frameCount: frameCount, timescale: timescale, rotated: rotated, asymmetric: asymmetric)
        // Keep the encoder alive across suspension; callbacks need not retain it in a cycle.
        defer { withExtendedLifetime(encoder) {} }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            encoder.start { continuation.resume(with: $0) }
        }
    }

    private init(destination: URL, width: Int, height: Int, frameCount: Int, timescale: Int32,
                 rotated: Bool, asymmetric: Bool) throws {
        guard (16...1920).contains(width), (16...1080).contains(height), (1...30).contains(frameCount), timescale > 0 else {
            throw NSError(domain: "SyntheticMovieWriter", code: 1)
        }
        self.destination = destination
        self.width = width; self.height = height; self.frameCount = frameCount
        self.timescale = timescale; self.asymmetric = asymmetric
        writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = false
        if rotated { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0) }
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        guard writer.canAdd(input) else { throw failure("Encoder cannot add video input") }
        writer.add(input)
    }

    private func start(completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            self.completion = completion
            startedAt = ProcessInfo.processInfo.systemUptime
            phase = "starting writer"
            guard writer.startWriting() else { finish(.failure(writer.error ?? failure("Encoder did not start"))); return }
            writer.startSession(atSourceTime: .zero)
            phase = "waiting for frames"
            let deadline = DispatchWorkItem { [weak self] in
                guard let self, !self.completed else { return }
                let elapsed = ProcessInfo.processInfo.systemUptime - self.startedAt
                let diagnostic = "Synthetic encoder exceeded 30-second budget: phase=\(self.phase), frames=\(self.nextFrame)/\(self.frameCount), status=\(self.writer.status.rawValue), elapsed=\(elapsed), writerError=\(String(describing: self.writer.error))"
                self.writer.cancelWriting()
                self.finish(.failure(self.failure(diagnostic)))
            }
            self.deadline = deadline
            queue.asyncAfter(deadline: .now() + 30, execute: deadline)
            input.requestMediaDataWhenReady(on: queue) { [weak self] in self?.appendReadyFrames() }
        }
    }

    private func appendReadyFrames() {
        guard !completed, nextFrame < frameCount else { return }
        do {
            while input.isReadyForMoreMediaData, nextFrame < frameCount {
                phase = "appending frame \(nextFrame)"
                var buffer: CVPixelBuffer?
                let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
                guard status == kCVReturnSuccess, let buffer else { throw failure("Pixel buffer creation failed") }
                CVPixelBufferLockBaseAddress(buffer, [])
                guard let base = CVPixelBufferGetBaseAddress(buffer) else {
                    CVPixelBufferUnlockBaseAddress(buffer, []); throw failure("Pixel buffer has no base address")
                }
                memset(base, Int32((64 + nextFrame * 32) % 256), CVPixelBufferGetBytesPerRow(buffer) * height)
                if asymmetric {
                    let pixels = base.assumingMemoryBound(to: UInt8.self), rowBytes = CVPixelBufferGetBytesPerRow(buffer)
                    for y in 0..<height/2 { for x in 0..<width/2 {
                        let offset = y * rowBytes + x * 4
                        pixels[offset] = 220; pixels[offset+1] = 30; pixels[offset+2] = 100; pixels[offset+3] = 255
                    } }
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(nextFrame), timescale: timescale)) else {
                    throw writer.error ?? failure("Frame append failed")
                }
                nextFrame += 1
            }
            if nextFrame == frameCount {
                phase = "finishing writer"
                writer.endSession(atSourceTime: CMTime(value: Int64(frameCount), timescale: timescale))
                input.markAsFinished()
                writer.finishWriting { [weak self] in
                    guard let self else { return }
                    self.queue.async { [weak self] in
                        guard let self, !self.completed else { return }
                        if self.writer.status == .completed { self.finish(.success(())) }
                        else { self.finish(.failure(self.writer.error ?? self.failure("Encoder did not finish"))) }
                    }
                }
            } else { phase = "waiting for frame \(nextFrame)" }
        } catch { writer.cancelWriting(); finish(.failure(error)) }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !completed else { return }
        completed = true
        deadline?.cancel(); deadline = nil
        if case .failure = result { try? FileManager.default.removeItem(at: destination) }
        let completion = self.completion; self.completion = nil
        completion?(result)
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "SyntheticMovieWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
