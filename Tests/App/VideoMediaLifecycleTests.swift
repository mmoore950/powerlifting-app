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

    @MainActor
    func testGeneratedLossSeekUsesActualPTSAndRejectsDelayedObsoleteCompletions() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("loss-review.mov")
        try await SyntheticMovieWriter.write(to: source)
        let probe = DelayedLossSeek()
        defer { probe.finishAll() }
        let model = VideoModel(store: VideoImportStore(rootDirectory: root.appendingPathComponent("managed")),
            lossSeek: probe.seek)
        await model.importFile(source).value
        model.seek(0.1); model.setEnd()
        await model.analyze(mode: .automatic).value
        XCTAssertNil(model.error)
        let analysis = try XCTUnwrap(model.analysisResult)
        let run = try XCTUnwrap(model.lossRuns.first)
        let actualPTS = analysis.timestamps[run.firstSampleIndex]
        XCTAssertNil(model.previousLossRunIndex); XCTAssertEqual(model.nextLossRunIndex, 0)

        let first = model.reviewLossRun(0)
        try await probe.waitForRequest(0)
        XCTAssertEqual(probe.times[0].value, Int64(actualPTS.value))
        XCTAssertEqual(probe.times[0].timescale, actualPTS.timescale)
        XCTAssertEqual(probe.times[0].epoch, actualPTS.epoch)
        XCTAssertNil(model.selectedLossRunIndex); XCTAssertTrue(model.lossSeekPending)
        let player = try XCTUnwrap(model.player)
        let completed = await player.seek(to: probe.times[0], toleranceBefore: .zero, toleranceAfter: .zero)
        XCTAssertTrue(completed)
        probe.finish(0, completed: completed); await first.value
        XCTAssertEqual(model.selectedLossRunIndex, 0); XCTAssertFalse(model.lossSeekPending)
        XCTAssertNotNil(model.lossReviewMessage)
        if model.lossRuns.count == 1 { XCTAssertNil(model.nextLossRunIndex) }

        let queued = model.reviewLossRun(0)
        model.seek(0.05)
        await queued.value
        XCTAssertEqual(probe.times.count, 1, "Cancelled queued jump must not issue a seek")

        let scrubbed = model.reviewLossRun(0)
        try await probe.waitForRequest(1)
        model.seek(0.05)
        probe.finish(1, completed: true); await scrubbed.value
        XCTAssertNil(model.selectedLossRunIndex); XCTAssertNil(model.lossReviewMessage)
        XCTAssertFalse(model.lossSeekPending)

        let played = model.reviewLossRun(0)
        try await probe.waitForRequest(2)
        model.togglePlayback()
        probe.finish(2, completed: true); await played.value
        XCTAssertNil(model.selectedLossRunIndex); XCTAssertFalse(model.lossSeekPending)
        model.pause()

        let older = model.reviewLossRun(0)
        try await probe.waitForRequest(3)
        let newer = model.reviewLossRun(0)
        try await probe.waitForRequest(4)
        probe.finish(3, completed: true); await older.value
        XCTAssertTrue(model.lossSeekPending); XCTAssertNil(model.selectedLossRunIndex)
        probe.finish(4, completed: false); await newer.value
        XCTAssertFalse(model.lossSeekPending); XCTAssertNil(model.selectedLossRunIndex)
        XCTAssertNotNil(model.error); XCTAssertNil(model.lossReviewMessage)

        let replacedAnalysis = model.reviewLossRun(0)
        try await probe.waitForRequest(5)
        await model.analyze(mode: .automatic).value
        XCTAssertNotEqual(model.analysisResult?.analysisID, analysis.analysisID)
        probe.finish(5, completed: true); await replacedAnalysis.value
        XCTAssertNil(model.selectedLossRunIndex); XCTAssertNil(model.lossReviewMessage)

        let trimmed = model.reviewLossRun(0)
        try await probe.waitForRequest(6)
        model.setEnd()
        probe.finish(6, completed: true); await trimmed.value
        XCTAssertNil(model.analysisResult); XCTAssertTrue(model.lossRuns.isEmpty)
        XCTAssertNil(model.selectedLossRunIndex); XCTAssertNil(model.nextLossRunIndex)

        model.seek(0.1); model.setEnd()
        await model.analyze(mode: .automatic).value
        let replacedClip = model.reviewLossRun(0)
        try await probe.waitForRequest(7)
        await model.importFile(source).value
        probe.finish(7, completed: true); await replacedClip.value
        XCTAssertNil(model.analysisResult); XCTAssertNil(model.selectedLossRunIndex)
        XCTAssertFalse(model.lossSeekPending)
        await model.removeVideo()
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("media-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}

/// Holds only loss-review completions; the first case separately exercises real AVPlayer seek.
@MainActor
private final class DelayedLossSeek {
    private var continuations: [Int: CheckedContinuation<Bool, Never>] = [:]
    private var waiters: [Int: CheckedContinuation<Void, Error>] = [:]
    private(set) var times: [CMTime] = []
    func seek(_ player: AVPlayer, _ time: CMTime) async -> Bool {
        await withCheckedContinuation { continuation in
            let index = times.count
            times.append(time); continuations[index] = continuation
            waiters.removeValue(forKey: index)?.resume()
        }
    }
    func waitForRequest(_ index: Int) async throws {
        if times.indices.contains(index) { return }
        let deadline = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            waiters.removeValue(forKey: index)?.resume(throwing: NSError(domain: "LossSeekTest", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Expected loss seek was not issued within 5 seconds"]))
        }
        defer { deadline.cancel() }
        try await withCheckedThrowingContinuation { waiters[index] = $0 }
    }
    func finish(_ index: Int, completed: Bool) {
        continuations.removeValue(forKey: index)?.resume(returning: completed)
    }
    func finishAll() {
        let pending = continuations.values; continuations = [:]
        for continuation in pending { continuation.resume(returning: false) }
        let pendingWaits = waiters.values; waiters = [:]
        for waiter in pendingWaits { waiter.resume(throwing: CancellationError()) }
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
