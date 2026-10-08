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
                            Text("\(analysis.mode.rawValue) · \(analysis.timestamps.count) actual-time frames · \(analysis.gaps) gaps · \(analysis.elapsed.formatted(.number.precision(.fractionLength(1)))) s processing").font(.caption)
                            Text("Automatic shape/continuity scores are uncalibrated heuristics. Manual mode uses Vision confidence; neither establishes bar identity accuracy.").font(.caption)
                        }
                        Text("Pause and tap the near-side bar hub to mark a manual reference point. These points are annotations, not automatic tracking. Points across gaps are never joined into an invented path.").font(.caption)
                        Text("\(model.trace?.samples.filter { $0.kind == .manualReference }.count ?? 0) manual reference points")
                        Button("Clear reference points", action: model.clearTrace)
                        Button("Remove imported copy", role: .destructive) { Task { await model.removeVideo() } }.disabled(model.processing)
                        Text("Removing this copy leaves the original in Photos or Files. Import replacement also removes the previous managed copy. No velocity or calibrated distance is computed.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ContentUnavailableView("Import a side-angle rep", systemImage: "video", description: Text("Choose a local squat, bench or deadlift clip. No sample tracking path is presented as a real result."))
                    }
                    Button("Clear all imported copies", role: .destructive) { Task { await model.clearManagedCopies() } }
                        .disabled(model.importing || photoImporting || model.processing)
                }.padding()
            }.navigationTitle("Bar path")
                .fileImporter(isPresented: $files, allowedContentTypes: [.movie]) { result in
                    do { pickerError = nil; model.importFile(try result.get()) }
                    catch { pickerError = error.localizedDescription }
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
                .onDisappear { model.pause(); model.cancelProcessing() }
                .onChange(of: scenePhase) { _, phase in if phase != .active { model.pause(); model.cancelProcessing() } }
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
        }.accessibilityLabel("Video preview with manual reference point overlay")
    }
}
