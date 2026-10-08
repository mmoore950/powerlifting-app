import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers
import LiftingCore

@MainActor
struct VideoAnalysisView: View {
    @StateObject private var model = VideoModel()
    @State private var files = false
    @State private var picked: PhotosPickerItem?
    @State private var photoImporting = false
    @State private var pickerError: String?
    @State private var analysisMode = BarAnalysisMode.automatic
    @State private var annotationLift = ""
    @State private var exportPickerPackage: AnnotationExportPresentation?
    @State private var exportPickerState = AnnotationExportPickerState()
    @State private var exportPresentationTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Videos stay on your device. Experimental automatic identification needs real-video validation.").font(.subheadline)
                    HStack {
                        PhotosPicker(selection: $picked, matching: .videos) { Label("Photos", systemImage: "photo") }
                        Button { files = true } label: { Label("Files", systemImage: "folder") }
                    }.buttonStyle(.bordered).disabled(model.importing || photoImporting || model.processing)
                    if model.importing || photoImporting { ProgressView("Importing local video") }
                    if let error = pickerError ?? model.error { Text(error).foregroundStyle(.orange) }
                    if let video = model.video, let player = model.player {
                        VideoPreview(player: player, video: video, trace: model.trace, seconds: model.seconds,
                            automatic: model.analysisResult?.mode == .automatic, mark: model.mark)
                            .id(video.url).frame(height: 300).background(.black).clipShape(RoundedRectangle(cornerRadius: 12))
                        HStack {
                            Button { model.togglePlayback() } label: { Label(model.playing ? "Pause" : "Play rep", systemImage: model.playing ? "pause.fill" : "play.fill") }
                            Text("\(model.seconds.formatted(.number.precision(.fractionLength(2)))) s").monospacedDigit()
                        }
                        Slider(value: Binding(get: { model.seconds }, set: model.seek), in: 0...video.duration)
                            .accessibilityLabel("Video playhead in seconds").disabled(model.processing)
                        Text("Rep: \(model.start.formatted(.number.precision(.fractionLength(2))))–\(model.end.formatted(.number.precision(.fractionLength(2)))) s · max 30 seconds")
                        HStack { Button("Start here", action: model.setStart); Button("End here", action: model.setEnd) }
                            .buttonStyle(.bordered).disabled(model.processing)
                        Picker("Identification mode", selection: $analysisMode) {
                            ForEach(BarAnalysisMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.disabled(model.processing)
                        Text(analysisMode == .automatic ? "Circles and motion are only candidate evidence. Ambiguity, unreliable scene motion or loss produce gaps; a selected object still needs visual verification." : "Manual mode tracks the region you identify. Seek to rep start and tap the hub first. It does not automatically identify the bar.").font(.caption)
                        if model.processing {
                            ProgressView(value: model.processingProgress)
                            Text(model.processingStatus).font(.caption)
                            Button(model.cancelling ? "Cancelling…" : "Cancel processing", action: model.cancelProcessing).disabled(model.cancelling)
                        } else {
                            Button("Analyze selected rep") { model.analyze(mode: analysisMode) }.buttonStyle(.borderedProminent)
                            if !model.processingStatus.isEmpty { Text(model.processingStatus).font(.caption) }
                        }
                        if let analysis = model.analysisResult {
                            Text("\(analysis.mode.rawValue) · \(analysis.timestamps.count) actual-time frames · \(analysis.gaps) abstaining frames · \(analysis.elapsed.formatted(.number.precision(.fractionLength(1)))) s processing").font(.caption)
                            Text("Automatic shape/continuity scores are uncalibrated heuristics. Manual mode uses Vision confidence; neither establishes bar identity accuracy.").font(.caption)
                            Text("\(model.lossRuns.reduce(0) { $0 + $1.frameCount }) abstaining frames in \(model.lossRuns.count) consecutive loss episodes.")
                                .font(.caption).accessibilityAddTraits(.isHeader)
                            if !model.lossRuns.isEmpty {
                                HStack {
                                    Button("Previous loss") {
                                        if let index = model.previousLossRunIndex { model.reviewLossRun(index) }
                                    }.disabled(model.previousLossRunIndex == nil || model.processing || model.importing)
                                        .accessibilityHint("Pauses and seeks to the first observed sample of the previous loss episode.")
                                    Button(model.selectedLossRunIndex == nil ? "Review first loss" : "Next loss") {
                                        if let index = model.nextLossRunIndex { model.reviewLossRun(index) }
                                    }.disabled(model.nextLossRunIndex == nil || model.processing || model.importing)
                                        .accessibilityHint("Pauses and seeks to the first observed sample of the next loss episode. Does not restart tracking.")
                                }.buttonStyle(.bordered)
                                if model.lossSeekPending { ProgressView("Seeking to loss sample") }
                                if let message = model.lossReviewMessage {
                                    Text(message).font(.caption).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                }
                                Text("Loss episodes group consecutive decoded samples with no accepted target. They do not establish the cause or a continuous missing interval. Manual taps remain annotations; a new manual analysis starts from the selected rep start.")
                                    .font(.caption).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("No explicit lost samples in this analysis. This does not establish correct target identification.").font(.caption)
                            }
                        }
                        Text("Pause and tap the near-side bar hub to mark a manual reference point. These points are annotations, not automatic tracking. Points across gaps are never joined into an invented path.").font(.caption)
                        Text("\(model.trace?.samples.filter { $0.kind == .manualReference }.count ?? 0) manual reference points")
                        Button("Clear reference points", action: model.clearTrace)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Development annotation export").font(.headline)
                            Text("Select a window of at most one second. The export includes the WHOLE imported movie, native frames and analysis; labels are still required.").font(.caption)
                            Picker("Lift for annotation", selection: $annotationLift) {
                                Text("Choose lift").tag("")
                                Text("Squat").tag("squat"); Text("Bench").tag("bench"); Text("Deadlift").tag("deadlift")
                            }.disabled(model.processing || model.savingAnnotationExport)
                            let movieBytes = (try? video.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                            Text("Whole imported movie: \(ByteCountFormatter.string(fromByteCount: Int64(movieBytes), countStyle: .file)). Files lets you choose an on-device or cloud destination.").font(.caption)
                            Button("Export annotation window") {
                                _ = model.prepareAnnotationExport(lift: annotationLift, mode: analysisMode)
                            }.buttonStyle(.bordered)
                                .disabled(annotationLift.isEmpty || model.end <= model.start || model.end - model.start > 1 || model.processing || model.importing || model.savingAnnotationExport || model.preparedAnnotationExport != nil || model.annotationExportRecoveryNeeded)
                        }
                        Button("Remove imported copy", role: .destructive) { Task { await model.removeVideo() } }.disabled(model.processing)
                        Text("Removing this copy leaves the original in Photos or Files. Import replacement also removes the previous managed copy. No velocity or calibrated distance is computed.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ContentUnavailableView("Import a side-angle rep", systemImage: "video", description: Text("Choose a local squat, bench or deadlift clip. No sample tracking path is presented as a real result."))
                    }
                    if let package = model.preparedAnnotationExport {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Annotation package ready").font(.headline)
                            Text("Includes the whole \(ByteCountFormatter.string(fromByteCount: Int64(package.sourceBytes), countStyle: .file)) movie · package \(ByteCountFormatter.string(fromByteCount: Int64(package.packageBytes), countStyle: .file)).").font(.caption)
                            Button(model.savingAnnotationExport ? "Verifying / saving…" : "Save annotation package to Files") {
                                exportPresentationTask = Task {
                                    var acquired: PreparedAnnotationExport?
                                    do {
                                        let lease = try await model.beginSavingAnnotationExport()
                                        acquired = lease
                                        try Task.checkCancellation()
                                        exportPickerPackage = try exportPickerState.begin(lease)
                                    } catch {
                                        if let acquired { await model.finishSavingAnnotationExport(acquired.id, saved: false) }
                                    }
                                }
                            }.buttonStyle(.borderedProminent).disabled(model.processing || model.savingAnnotationExport)
                            Button("Discard prepared export", role: .destructive) { Task { await model.discardAnnotationExport() } }
                                .disabled(model.processing || model.savingAnnotationExport)
                        }
                    } else if model.annotationExportRecoveryNeeded {
                        Button("Discard unreadable prepared export", role: .destructive) { Task { await model.discardAnnotationExport() } }
                            .disabled(model.processing || model.savingAnnotationExport)
                    }
                    if !model.annotationExportStatus.isEmpty { Text(model.annotationExportStatus).font(.caption) }
                    Button("Clear all imported copies", role: .destructive) { Task { await model.clearManagedCopies() } }
                        .disabled(model.importing || photoImporting || model.processing)
                }.padding()
            }.navigationTitle("Bar path")
                .fileImporter(isPresented: $files, allowedContentTypes: [.movie]) { result in
                    do { pickerError = nil; model.importFile(try result.get()) }
                    catch { pickerError = error.localizedDescription }
                }
                .task { await model.recoverAnnotationExport() }
                .sheet(item: $exportPickerPackage) { presentation in
                    AnnotationExportPicker(package: presentation.package, requestDismissal: { saved, message in
                        guard exportPickerState.requestDismissal(presentation.id, saved: saved, message: message) else { return }
                        exportPickerPackage = nil
                    }, dismantled: {
                        guard let completion = exportPickerState.dismantle(presentation.id) else { return }
                        Task { await model.finishSavingAnnotationExport(completion.packageID, saved: completion.saved, message: completion.message) }
                    })
                }
                .task(id: picked) {
                    guard let picked else { return }
                    photoImporting = true; pickerError = nil
                    defer { photoImporting = false }
                    do {
                        guard let movie = try await picked.loadTransferable(type: PickedMovie.self) else { throw VideoImportError.unsupported }
                        if Task.isCancelled { try? FileManager.default.removeItem(at: movie.url); return }
                        model.importFile(movie.url, temporary: true)
                    } catch { if !Task.isCancelled { pickerError = error.localizedDescription } }
                }
                .onDisappear {
                    model.pause(); model.cancelProcessing()
                    if exportPickerPackage == nil { exportPresentationTask?.cancel() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        model.pause(); model.cancelProcessing()
                        if exportPickerPackage == nil { exportPresentationTask?.cancel() }
                    }
                }
        }
    }
}

private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let report: (CGRect) -> Void
    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var report: ((CGRect) -> Void)?
        private var readiness: NSKeyValueObservation?
        override init(frame: CGRect) {
            super.init(frame: frame)
            readiness = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.setNeedsLayout() }
            }
        }
        required init?(coder: NSCoder) { fatalError("Programmatic video surface only") }
        override func layoutSubviews() {
            super.layoutSubviews()
            report?(playerLayer.isReadyForDisplay ? playerLayer.videoRect : .zero)
        }
    }
    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView(frame: .zero); view.playerLayer.videoGravity = .resizeAspect; return view
    }
    func updateUIView(_ view: PlayerView, context: Context) {
        view.report = { rect in DispatchQueue.main.async { report(rect) } }
        view.playerLayer.player = player; view.setNeedsLayout()
    }
    static func dismantleUIView(_ view: PlayerView, coordinator: ()) { view.playerLayer.player = nil }
}

private struct VideoPreview: View {
    let player: AVPlayer
    let video: ImportedVideo
    let trace: VideoTrace?
    let seconds: Double
    let automatic: Bool
    let mark: (VideoPoint) -> Void
    @State private var videoRect: CGRect = .zero
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PlayerSurface(player: player) { rect in if videoRect != rect { videoRect = rect } }
                if let fit = try? VideoFit(x: Double(videoRect.minX), y: Double(videoRect.minY),
                    width: Double(videoRect.width), height: Double(videoRect.height)) {
                    Canvas { context, _ in
                        for segment in trace?.segments(through: seconds) ?? [] {
                            var path = Path()
                            for (index, point) in segment.enumerated() {
                                let mapped = fit.screenPoint(point)
                                let location = CGPoint(x: CGFloat(mapped.x), y: CGFloat(mapped.y))
                                if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
                                context.fill(Path(ellipseIn: CGRect(x: location.x - 3, y: location.y - 3, width: 6, height: 6)), with: .color(automatic ? .mint : .yellow))
                            }
                            context.stroke(path, with: .color(automatic ? .mint : .yellow), lineWidth: 2)
                        }
                    }.allowsHitTesting(false)
                    Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { value in
                        if let point = fit.imagePoint(screenX: Double(value.location.x), screenY: Double(value.location.y)) { mark(point) }
                    })
                }
            }
        }.accessibilityLabel("Video preview with experimental tracking and manual reference overlays")
    }
}
