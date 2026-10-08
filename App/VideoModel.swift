import Foundation
import AVFoundation
import SwiftUI
import LiftingCore

@MainActor
final class VideoModel: ObservableObject {
    @Published private(set) var video: ImportedVideo?
    @Published private(set) var player: AVPlayer?
    @Published private(set) var importing = false
    @Published private(set) var error: String?
    @Published private(set) var playing = false
    @Published private(set) var seconds = 0.0
    @Published private(set) var start = 0.0
    @Published private(set) var end = 0.0
    @Published private(set) var trace: VideoTrace?
    @Published private(set) var processing = false
    @Published private(set) var cancelling = false
    @Published private(set) var processingProgress = 0.0
    @Published private(set) var processingStatus = ""
    @Published private(set) var analysisResult: BarAnalysisResult?
    private let store = VideoImportStore()
    private let analyzer = BarAnalysisService()
    private let predictionExporter = BarPredictionExporter()
    private var analysisTask: Task<Void, Never>?
    private var analysisGeneration = 0
    private var observerCleanup: (@MainActor @Sendable () -> Void)?
    private var generation = 0
    private var playerGeneration = 0
    private var playbackRequest = 0
    private var itemObservation: NSKeyValueObservation?
    private var importTask: Task<Void, Never>?

    func importFile(_ url: URL, temporary: Bool = false) {
        generation += 1; let request = generation
        importTask?.cancel()
        pause()
        cancelProcessing()
        let previousAnalysis = analysisTask
        importing = true; error = nil
        importTask = Task {
            defer {
                if temporary { try? FileManager.default.removeItem(at: url) }
                if request == generation { importing = false }
            }
            do {
                await previousAnalysis?.value
                try Task.checkCancellation()
                let imported = try await store.ingest(url)
                guard request == generation, !Task.isCancelled else { try? await store.remove(imported.url); return }
                let previous = video?.url
                detachPlayer()
                video = imported; start = 0; end = min(10, imported.duration); seconds = 0; trace = nil; analysisResult = nil; processingStatus = ""
                let next = AVPlayer(url: imported.url)
                player = next
                let playerRequest = playerGeneration
                let observer = next.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
                    Task { @MainActor [weak self] in self?.tick(time.seconds, generation: playerRequest) }
                }
                observerCleanup = { next.removeTimeObserver(observer) }
                itemObservation = next.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    guard item.status == .failed else { return }
                    let message = item.error?.localizedDescription ?? "Video playback failed."
                    Task { @MainActor [weak self] in
                        guard let self, self.playerGeneration == playerRequest else { return }
                        self.pause(); self.error = message
                    }
                }
                if let previous { try? await store.remove(previous) }
            } catch {
                if request == generation, !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    func togglePlayback() {
        guard !processing, let player else { return }
        if playing { pause() }
        else {
            playbackRequest += 1; let request = playbackRequest
            let destination = start
            let needsSeek = seconds < start || seconds >= end
            Task {
                if needsSeek {
                    let completed = await player.seek(to: CMTime(seconds: destination, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    guard completed else { return }
                }
                guard request == playbackRequest else { return }
                player.play(); playing = true
            }
        }
    }
    func pause() { playbackRequest += 1; player?.pause(); playing = false }
    func seek(_ value: Double) {
        guard let video, value.isFinite else { return }
        pause(); seconds = min(video.duration, max(0, value))
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func setStart() {
        guard !processing, let video else { return }
        start = min(seconds, max(0, video.duration - 0.01))
        end = min(video.duration, max(start + 0.01, min(end, start + 30)))
        trace = nil; analysisResult = nil; pause()
    }
    func setEnd() {
        guard !processing, let video else { return }
        end = min(video.duration, max(0.01, seconds))
        start = max(0, max(min(start, end - 0.01), end - 30))
        trace = nil; analysisResult = nil; pause()
    }
    func mark(_ point: VideoPoint) {
        guard !processing else { return }
        pause()
        let actual = player?.currentTime().seconds ?? seconds
        guard actual.isFinite, actual >= start, actual <= end else { error = "Choose a frame inside the selected rep."; return }
        seconds = actual
        if analysisResult != nil { trace = nil; analysisResult = nil }
        do {
            var samples = trace?.samples ?? []
            samples.removeAll { abs($0.seconds - seconds) < 0.03 }
            samples.append(try VideoTraceSample(seconds: seconds, point: point, confidence: 1, kind: .manualReference))
            trace = try VideoTrace(start: start, end: end, samples: samples.sorted { $0.seconds < $1.seconds })
            error = nil
        } catch { self.error = "Unable to save this manual reference point." }
    }
    func clearTrace() { guard !processing else { return }; trace = nil; analysisResult = nil }
    func analyze(mode: BarAnalysisMode) {
        guard !processing, !importing, let video else { return }
        let seed = trace?.samples.first { $0.kind == .manualReference && abs($0.seconds-start) <= 0.05 }?.point
        if mode == .manual, seed == nil { error = "Seek to rep start and tap a manual reference point first."; return }
        pause(); error = nil; processing = true; cancelling = false; processingProgress = 0; processingStatus = "Preparing upright frames"
        analysisGeneration += 1; let run = analysisGeneration, clipGeneration = generation
        let trimStart = start, trimEnd = end
        analysisTask = Task {
            defer { if run == analysisGeneration { processing = false; cancelling = false } }
            do {
                let result = try await analyzer.analyze(url: video.url, start: trimStart, end: trimEnd, mode: mode, manualPoint: seed) { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self, self.analysisGeneration == run, self.generation == clipGeneration, self.processing, !self.cancelling else { return }
                        self.processingProgress = update.fraction; self.processingStatus = update.reason
                    }
                }
                guard !Task.isCancelled, run == analysisGeneration, clipGeneration == generation else { return }
                trace = result.trace; analysisResult = result; processingProgress = 1
                processingStatus = result.gaps == result.timestamps.count ? "No target accepted; all decoded frames abstained" : "Experimental processing complete; verify the selected target"
                seek(trimStart)
            } catch {
                guard run == analysisGeneration, clipGeneration == generation else { return }
                if error is CancellationError || Task.isCancelled { processingStatus = "Processing cancelled" }
                else { self.error = error.localizedDescription; processingStatus = "Processing failed; previous trace retained" }
            }
        }
    }
    func cancelProcessing() {
        if processing { cancelling = true; processingStatus = "Cancelling and releasing frame resources" }
        analysisTask?.cancel()
    }
    /// Developer-local diagnostics hook. Caller supplies manifest identity and chooses local storage.
    /// Returning Data avoids publishing an obsolete result after a clip change or clear operation.
    func predictionJSON(context: BarPredictionContext) async throws -> Data {
        guard !processing, !importing, let video, let result = analysisResult else { throw BarPredictionError.unavailable }
        let clipGeneration = generation, analysis = analysisGeneration
        let data = try await predictionExporter.data(result: result, mediaURL: video.url, context: context)
        try Task.checkCancellation()
        guard generation == clipGeneration, analysisGeneration == analysis, self.video?.url == video.url,
              analysisResult != nil, !processing, !importing else { throw BarPredictionError.unavailable }
        return data
    }
    func clearManagedCopies() async {
        await removeVideo()
        do { try await store.clearManagedCopies(); error = nil }
        catch { self.error = "Removing managed copies failed: \(error.localizedDescription)" }
    }
    func removeVideo() async {
        generation += 1; importTask?.cancel(); importing = false
        cancelProcessing(); await analysisTask?.value
        let previous = video?.url
        detachPlayer(); video = nil; trace = nil; analysisResult = nil; seconds = 0; start = 0; end = 0
        if let previous {
            do { try await store.remove(previous); error = nil }
            catch { self.error = "Playback closed, but removing the imported copy failed: \(error.localizedDescription)" }
        }
    }
    private func tick(_ value: Double, generation request: Int) {
        guard request == playerGeneration, let video, value.isFinite else { return }
        seconds = min(video.duration, max(0, value))
        if playing && value >= end { pause() }
    }
    private func detachPlayer() {
        pause()
        playerGeneration += 1; itemObservation = nil
        observerCleanup?(); observerCleanup = nil
        player?.replaceCurrentItem(with: nil); player = nil
    }
    deinit {
        importTask?.cancel()
        analysisTask?.cancel()
        // Deinit may run off the main actor. Retain only the Sendable cleanup closure,
        // which owns the matching player/token and performs removal on the main actor.
        if let observerCleanup { Task { @MainActor in observerCleanup() } }
    }
}
