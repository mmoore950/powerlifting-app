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
    @Published private(set) var analysisResult: BarAnalysisResult? { didSet { resetLossReview() } }
    @Published private(set) var preparedAnnotationExport: PreparedAnnotationExport?
    @Published private(set) var savingAnnotationExport = false
    @Published private(set) var annotationExportRecoveryNeeded = false
    @Published private(set) var annotationExportStatus = ""
    private let store: VideoImportStore
    private let annotationExports: AnnotationExportStore
    private let analyzer = BarAnalysisService()
    private let lossSeek: @MainActor (AVPlayer, CMTime) async -> Bool
    private let predictionExporter = BarPredictionExporter()
    private var analysisTask: Task<Void, Never>?
    private var captureTask: Task<URL, Error>?
    private var captureAuthorization: BarCaptureAuthorization?
    private var portableTask: Task<PreparedAnnotationExport, Error>?
    private var portableAuthorization: BarCaptureAuthorization?
    private var analysisGeneration = 0
    private var observerCleanup: (@MainActor @Sendable () -> Void)?
    private var generation = 0
    private var playerGeneration = 0
    @Published private(set) var selectedLossRunIndex: Int?
    @Published private(set) var lossSeekPending = false
    @Published private(set) var lossReviewMessage: String?
    private var lossJumpTask: Task<Void, Never>?
    var lossRuns: [VideoLossRun] { analysisResult?.trace.lossRuns ?? [] }
    var nextLossRunIndex: Int? {
        let next = selectedLossRunIndex.map { $0 + 1 } ?? 0
        return lossRuns.indices.contains(next) ? next : nil
    }
    var previousLossRunIndex: Int? {
        guard let selectedLossRunIndex, selectedLossRunIndex > 0 else { return nil }
        return selectedLossRunIndex - 1
    }
    private var playbackRequest = 0
    private var itemObservation: NSKeyValueObservation?
    private var importTask: Task<Void, Never>?

    init(store: VideoImportStore = VideoImportStore(), annotationExports: AnnotationExportStore = .shared,
         lossSeek: @escaping @MainActor (AVPlayer, CMTime) async -> Bool = { player, time in
             await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
         }) {
        self.store = store; self.annotationExports = annotationExports; self.lossSeek = lossSeek
    }

    @discardableResult
    func importFile(_ url: URL, temporary: Bool = false) -> Task<Void, Never> {
        // Revoke publication before changing the clip generation.
        cancelProcessing()
        generation += 1; let request = generation
        importTask?.cancel()
        pause()
        let previousAnalysis = analysisTask
        let previousCapture = captureTask
        let previousPortable = portableTask
        importing = true; error = nil
        let task = Task {
            defer {
                if temporary { try? FileManager.default.removeItem(at: url) }
                if request == generation { importing = false }
            }
            do {
                await previousAnalysis?.value
                _ = await previousCapture?.result
                _ = await previousPortable?.result
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
        importTask = task
        return task
    }
    func togglePlayback() {
        guard !processing, let player else { return }
        if playing { pause() }
        else {
            pause(); let request = playbackRequest
            let destination = start
            let needsSeek = seconds < start || seconds >= end
            Task {
                guard request == playbackRequest, self.player === player else { return }
                if needsSeek {
                    let completed = await player.seek(to: CMTime(seconds: destination, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    guard completed else { return }
                }
                guard request == playbackRequest else { return }
                player.play(); playing = true
            }
        }
    }
    func pause() {
        playbackRequest += 1
        lossJumpTask?.cancel(); lossJumpTask = nil
        if lossSeekPending { player?.currentItem?.cancelPendingSeeks() }
        lossSeekPending = false
        player?.pause(); playing = false
    }
    private func resetLossReview() {
        pause(); selectedLossRunIndex = nil; lossReviewMessage = nil
    }
    /// Navigation reviews an abstention; it never reinitializes or joins tracking.
    @discardableResult
    func reviewLossRun(_ index: Int) -> Task<Void, Never> {
        guard !processing, !importing, let video, let player, let analysis = analysisResult,
              lossRuns.indices.contains(index) else { return Task {} }
        pause(); selectedLossRunIndex = nil; lossReviewMessage = nil
        let sampleIndex = lossRuns[index].firstSampleIndex
        guard analysis.timestamps.indices.contains(sampleIndex) else {
            error = "This loss sample has no recorded presentation timestamp."
            return Task {}
        }
        let timestamp = analysis.timestamps[sampleIndex]
        guard let value = Int64(timestamp.value), timestamp.timescale > 0, timestamp.epoch == 0 else {
            error = "This loss sample has an unsupported presentation timestamp."
            return Task {}
        }
        let destination = CMTime(value: value, timescale: timestamp.timescale, flags: .valid, epoch: timestamp.epoch)
        guard destination.seconds == analysis.trace.samples[sampleIndex].seconds,
              destination.seconds >= start, destination.seconds <= end else {
            error = "This loss sample does not match the selected rep."
            return Task {}
        }
        lossSeekPending = true; error = nil
        let request = playbackRequest, playerIdentity = playerGeneration, clipIdentity = generation
        let analysisIdentity = analysis.analysisID
        let task = Task {
            defer {
                if request == playbackRequest { lossSeekPending = false; lossJumpTask = nil }
            }
            guard !Task.isCancelled, request == playbackRequest, playerIdentity == playerGeneration,
                  clipIdentity == generation, self.player === player, self.video?.url == video.url,
                  analysisResult?.analysisID == analysisIdentity else { return }
            let completed = await lossSeek(player, destination)
            guard !Task.isCancelled, request == playbackRequest, playerIdentity == playerGeneration,
                  clipIdentity == generation, self.player === player, self.video?.url == video.url,
                  analysisResult?.analysisID == analysisIdentity else { return }
            guard completed else {
                error = "Unable to seek to this loss sample. No reviewed frame was selected."
                return
            }
            let actual = player.currentTime().seconds
            guard actual.isFinite, actual >= 0, actual <= video.duration else {
                error = "Playback returned an unsupported time after the loss seek."
                return
            }
            seconds = actual; selectedLossRunIndex = index
            lossReviewMessage = "Loss episode \(index + 1) of \(lossRuns.count): requested observed sample at \(destination.seconds.formatted(.number.precision(.fractionLength(2)))) seconds. Verify the visible frame; navigation does not establish target identity."
        }
        lossJumpTask = task
        return task
    }
    func seek(_ value: Double) {
        guard let video, value.isFinite else { return }
        pause(); selectedLossRunIndex = nil; lossReviewMessage = nil
        seconds = min(video.duration, max(0, value))
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
    @discardableResult
    func analyze(mode: BarAnalysisMode) -> Task<Void, Never> {
        guard !processing, !importing, let video else { return Task {} }
        let seed = trace?.samples.first { $0.kind == .manualReference && abs($0.seconds-start) <= 0.05 }?.point
        if mode == .manual, seed == nil { error = "Seek to rep start and tap a manual reference point first."; return Task {} }
        pause(); error = nil; processing = true; cancelling = false; processingProgress = 0; processingStatus = "Preparing upright frames"
        analysisGeneration += 1; let run = analysisGeneration, clipGeneration = generation
        let trimStart = start, trimEnd = end
        let task = Task {
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
        analysisTask = task
        return task
    }
    func cancelProcessing() {
        captureAuthorization?.invalidate()
        portableAuthorization?.invalidate()
        if processing { cancelling = true; processingStatus = "Cancelling and releasing frame resources" }
        analysisTask?.cancel()
        captureTask?.cancel()
        portableTask?.cancel()
    }
    func recoverAnnotationExport() async {
        guard !processing, !savingAnnotationExport else { return }
        do {
            preparedAnnotationExport = try await annotationExports.recover()
            annotationExportRecoveryNeeded = false
        } catch {
            annotationExportRecoveryNeeded = true
            annotationExportStatus = "Recovering the prepared export failed: " + error.localizedDescription
        }
    }
    /// One joined task owns hashing, native capture and the portable movie copy.
    /// Cancellation/removal awaits it before deleting the managed source.
    @discardableResult
    func prepareAnnotationExport(lift: String, mode: BarAnalysisMode = .automatic,
                                 synthetic: Bool = false) -> Task<PreparedAnnotationExport, Error> {
        guard !processing, !importing, !savingAnnotationExport, preparedAnnotationExport == nil,
              !annotationExportRecoveryNeeded, let video, start.isFinite, end.isFinite,
              end > start, end - start <= 1, ["squat", "bench", "deadlift"].contains(lift) else {
            error = AnnotationExportError.state.localizedDescription
            return Task { throw AnnotationExportError.state }
        }
        let seed = trace?.samples.first { $0.kind == .manualReference && abs($0.seconds-start) <= 0.05 }?.point
        if mode == .manual, seed == nil {
            error = BarAnalysisError.manualPoint.localizedDescription
            return Task { throw BarAnalysisError.manualPoint }
        }
        pause(); error = nil; processing = true; cancelling = false; processingProgress = 0
        processingStatus = "Checking space and identifying the whole imported movie"
        analysisGeneration += 1; let run = analysisGeneration, clipGeneration = generation
        let trimStart = start, trimEnd = end
        let capturePermission = BarCaptureAuthorization(), publication = BarCaptureAuthorization()
        captureAuthorization = capturePermission; portableAuthorization = publication
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "unspecified"
        let modelID = BarAnalysisService.implementationID + "/app-build-" + build
        let task = Task<PreparedAnnotationExport, Error> {
            var work: AnnotationExportWork?, exporter: BarFrameBundleExporter?, completed: PreparedAnnotationExport?
            defer {
                if run == analysisGeneration {
                    processing = false; cancelling = false; portableTask = nil
                    portableAuthorization = nil; captureAuthorization = nil
                }
            }
            do {
                return try await withTaskCancellationHandler {
                    let current = try await annotationExports.begin(mediaURL: video.url); work = current
                    try Task.checkCancellation(); try publication.check()
                    guard generation == clipGeneration, analysisGeneration == run, self.video?.url == video.url else { throw AnnotationExportError.identity }
                    let context = BarFrameBundleContext(
                        prediction: BarPredictionContext(clipID: "window-" + current.id.uuidString,
                            expectedSHA256: current.sourceSHA256, modelID: modelID, synthetic: synthetic),
                        assetRoot: video.url.deletingLastPathComponent(), localPath: video.url.lastPathComponent,
                        sourceGroup: "recording-sha256-" + current.sourceSHA256, split: "development",
                        permissionEvidence: synthetic ? "Generated fixture for local lifecycle verification" : "User explicitly selected local annotation export; broader research consent unspecified",
                        lift: synthetic ? "synthetic" : lift, targetID: "near-side-hub")
                    let writer = try BarFrameBundleExporter(mediaURL: video.url, context: context,
                        destination: current.capture, authorization: capturePermission)
                    exporter = writer
                    let sink = try await writer.prepare()
                    processingStatus = "Capturing the selected native annotation window"
                    let result = try await analyzer.analyze(url: video.url, start: trimStart, end: trimEnd,
                        mode: mode, manualPoint: seed, capture: sink) { [weak self] update in
                        Task { @MainActor [weak self] in
                            guard let self, self.analysisGeneration == run, self.generation == clipGeneration,
                                  self.processing, !self.cancelling else { return }
                            self.processingProgress = update.fraction * 0.8; self.processingStatus = update.reason
                        }
                    }
                    try Task.checkCancellation(); try publication.check()
                    _ = try await writer.finish(result: result)
                    processingStatus = "Copying and verifying the whole imported movie"
                    let package = try await annotationExports.finish(current, context: context, authorization: publication)
                    completed = package
                    // Package publication has its own token; the capture token
                    // was consumed when writer.finish published its directory.
                    guard !Task.isCancelled, !cancelling, generation == clipGeneration,
                          analysisGeneration == run, self.video?.url == video.url else { throw AnnotationExportError.identity }
                    preparedAnnotationExport = package; annotationExportRecoveryNeeded = false
                    trace = result.trace; analysisResult = result; processingProgress = 1
                    processingStatus = "Annotation package prepared; choose Save to Files"
                    annotationExportStatus = "Development annotation export: labels and evaluation still required."
                    return package
                } onCancel: { capturePermission.invalidate(); publication.invalidate() }
            } catch {
                capturePermission.invalidate(); publication.invalidate()
                await exporter?.abort()
                do {
                    if let completed { try await annotationExports.discard(completed.id) }
                    if let work { try await annotationExports.abort(work) }
                } catch {
                    annotationExportRecoveryNeeded = true
                    annotationExportStatus = "Prepared-export cleanup needs attention: " + error.localizedDescription
                }
                if run == analysisGeneration, clipGeneration == generation {
                    processingStatus = Task.isCancelled ? "Annotation export cancelled; previous analysis retained" : "Annotation export failed; previous analysis retained"
                    if !Task.isCancelled { self.error = error.localizedDescription }
                }
                throw error
            }
        }
        portableTask = task
        return task
    }
    func beginSavingAnnotationExport() async throws -> PreparedAnnotationExport {
        guard let package = preparedAnnotationExport, !processing, !savingAnnotationExport else { throw AnnotationExportError.busy }
        savingAnnotationExport = true
        do {
            let lease = try await annotationExports.acquirePickerLease(package.id)
            if Task.isCancelled {
                await annotationExports.releasePickerLease(package.id)
                throw CancellationError()
            }
            return lease
        } catch {
            savingAnnotationExport = false; annotationExportStatus = error.localizedDescription
            throw error
        }
    }
    func finishSavingAnnotationExport(_ id: UUID, saved: Bool, message: String? = nil) async {
        await annotationExports.releasePickerLease(id)
        savingAnnotationExport = false
        annotationExportStatus = message ?? (saved ? "Files export completed. Keep the movie and all capture files together for labeling." : "Files export cancelled; the prepared package is retained for retry.")
    }
    func discardAnnotationExport() async {
        guard !processing, !savingAnnotationExport else { return }
        do {
            try await annotationExports.discard(preparedAnnotationExport?.id)
            preparedAnnotationExport = nil; annotationExportRecoveryNeeded = false
            annotationExportStatus = "Prepared export discarded. Saved Files copies are unchanged."
        } catch { annotationExportStatus = error.localizedDescription }
    }
    /// Explicit developer-local operation; no product button or implicit destination.
    /// The same analysis result produces both the PNG ledger and prediction JSON.
    @discardableResult
    func captureAnnotationBundle(context: BarFrameBundleContext, destination: URL,
                                 mode: BarAnalysisMode = .automatic) -> Task<URL, Error> {
        guard !processing, !importing, let video, end - start <= 1 else {
            return Task { throw BarFrameBundleError.state }
        }
        let seed = trace?.samples.first { $0.kind == .manualReference && abs($0.seconds-start) <= 0.05 }?.point
        if mode == .manual, seed == nil { return Task { throw BarAnalysisError.manualPoint } }
        pause(); error = nil; processing = true; cancelling = false; processingProgress = 0
        processingStatus = "Preparing native annotation frames"
        analysisGeneration += 1; let run = analysisGeneration, clipGeneration = generation
        let trimStart = start, trimEnd = end
        let authorization = BarCaptureAuthorization(); captureAuthorization = authorization
        let task = Task<URL, Error> {
            defer {
                if run == analysisGeneration {
                    processing = false; cancelling = false; captureTask = nil; captureAuthorization = nil
                }
            }
            var activeExporter: BarFrameBundleExporter?
            do {
                let exporter = try BarFrameBundleExporter(mediaURL: video.url, context: context,
                    destination: destination, authorization: authorization)
                activeExporter = exporter
                return try await withTaskCancellationHandler {
                    let sink = try await exporter.prepare()
                    let result = try await analyzer.analyze(url: video.url, start: trimStart, end: trimEnd, mode: mode,
                        manualPoint: seed, capture: sink) { [weak self] update in
                        Task { @MainActor [weak self] in
                            guard let self, self.analysisGeneration == run, self.generation == clipGeneration, self.processing, !self.cancelling else { return }
                            self.processingProgress = update.fraction; self.processingStatus = update.reason
                        }
                    }
                    guard !Task.isCancelled, generation == clipGeneration, analysisGeneration == run,
                          self.video?.url == video.url else { throw BarFrameBundleError.revoked }
                    let output = try await exporter.finish(result: result)
                    // Publication has already linearized against revocation. A later
                    // clip change cannot relabel the historical bundle or update UI.
                    if !Task.isCancelled, !cancelling, generation == clipGeneration, analysisGeneration == run, self.video?.url == video.url {
                        trace = result.trace; analysisResult = result; processingProgress = 1
                        processingStatus = "Native annotation bundle saved locally; labeling and evaluation still required"
                    }
                    return output
                } onCancel: { authorization.invalidate() }
            } catch {
                await activeExporter?.abort()
                authorization.invalidate()
                if run == analysisGeneration, clipGeneration == generation {
                    processingStatus = Task.isCancelled ? "Native annotation capture cancelled" : "Native annotation capture failed; previous result retained"
                    if !Task.isCancelled { self.error = error.localizedDescription }
                }
                throw error
            }
        }
        captureTask = task
        return task
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
        pause(); selectedLossRunIndex = nil; lossReviewMessage = nil
        cancelProcessing()
        generation += 1; importTask?.cancel(); importing = false
        await analysisTask?.value
        _ = await captureTask?.result
        _ = await portableTask?.result
        let previous = video?.url
        detachPlayer(); video = nil; trace = nil; analysisResult = nil; seconds = 0; start = 0; end = 0
        if let previous {
            do { try await store.remove(previous); error = nil }
            catch { self.error = "Playback closed, but removing the imported copy failed: \(error.localizedDescription)" }
        }
    }
    private func tick(_ value: Double, generation request: Int) {
        guard request == playerGeneration, !lossSeekPending, let video else { return }
        let actual = player?.currentTime().seconds ?? value
        guard actual.isFinite else { return }
        seconds = min(video.duration, max(0, actual))
        if playing && actual >= end { pause() }
    }
    private func detachPlayer() {
        pause()
        playerGeneration += 1; itemObservation = nil
        observerCleanup?(); observerCleanup = nil
        player?.replaceCurrentItem(with: nil); player = nil
    }
    deinit {
        lossJumpTask?.cancel()
        importTask?.cancel()
        analysisTask?.cancel()
        captureAuthorization?.invalidate(); captureTask?.cancel()
        portableAuthorization?.invalidate(); portableTask?.cancel()
        // Deinit may run off the main actor. Retain only the Sendable cleanup closure,
        // which owns the matching player/token and performs removal on the main actor.
        if let observerCleanup { Task { @MainActor in observerCleanup() } }
    }
}
