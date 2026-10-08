import Foundation

/// Geometry/appearance evidence is an experimental heuristic, not a bar-identity probability.
public struct BarCandidate: Sendable {
    public let center: VideoPoint
    public let radius: Double
    public let aspect: Double
    public let hubRatio: Double
    public let shapeScore: Double
    public let color: [Double]
    public init(center: VideoPoint, radius: Double, aspect: Double, hubRatio: Double,
                shapeScore: Double, color: [Double]) throws {
        guard radius.isFinite, radius > 0, radius <= 0.5, aspect.isFinite, (0.4...1).contains(aspect),
              hubRatio.isFinite, (0.04...0.35).contains(hubRatio), shapeScore.isFinite,
              (0...1).contains(shapeScore), color.count == 3,
              color.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw VideoTraceError.invalidGeometry }
        self.center = center; self.radius = radius; self.aspect = aspect; self.hubRatio = hubRatio
        self.shapeScore = shapeScore; self.color = color
    }
}

public struct BarSceneShift: Sendable {
    public let x: Double, y: Double
    public init(x: Double, y: Double) throws {
        guard x.isFinite, y.isFinite, abs(x) <= 0.03, abs(y) <= 0.03 else { throw VideoTraceError.invalidGeometry }
        self.x = x; self.y = y
    }
}

public struct BarDecision: Sendable {
    public let point: VideoPoint?
    public let score: Double
    public let targetID: String?
    public let kind: VideoTraceSample.Kind
    public let reason: String
}

/// Requires repeated annular shape, compensated motion and size dominance before choosing.
/// These conditions cannot establish semantic bar identity; real evaluation remains required.
public struct BarCandidateTracker: Sendable {
    private struct Track: Sendable {
        let id: Int
        var candidate: BarCandidate
        var last: Double
        var streak: Int
        var movement: Double
        var netX: Double = 0
        var netY: Double = 0
        var first: Double
        var velocityX: Double = 0
        var velocityY: Double = 0
    }
    private var tracks: [Track] = []
    private var nextID = 0
    private var locked: Track?
    private var lastTime: Double?
    private var recoveryCount = 0
    private var missing = false
    public init() {}
    public mutating func process(seconds: Double, candidates: [BarCandidate], scene: BarSceneShift?) throws -> BarDecision {
        guard seconds.isFinite, seconds >= 0, candidates.count <= 64,
              lastTime.map({ seconds > $0 }) ?? true else { throw VideoTraceError.invalidSample }
        let frameGap = lastTime.map { seconds - $0 } ?? 0
        lastTime = seconds
        guard let scene, frameGap <= 0.25 else {
            tracks = []; locked = nil; missing = false; recoveryCount = 0
            return gap("Camera evidence unavailable or frame interval too large")
        }
        let strong = candidates.filter { $0.shapeScore >= 0.65 }
        if var identity = locked {
            let elapsed = seconds - identity.last
            if elapsed > 0.75 {
                locked = nil; tracks = []; missing = false; recoveryCount = 0
                return gap("Identity expired; a new initialization is required")
            }
            let predictedX = identity.candidate.center.x + scene.x + identity.velocityX * elapsed
            let predictedY = identity.candidate.center.y + scene.y + identity.velocityY * elapsed
            let matches = strong.filter { compatible(identity.candidate, $0) &&
                hypot($0.center.x - predictedX, $0.center.y - predictedY) <= min(0.08, 0.025 + elapsed * 0.05) }
            guard matches.count == 1, let candidate = matches.first else {
                missing = true; recoveryCount = 0
                // Accumulate only reliable camera shift while identity is temporarily missing.
                if let moved = try? VideoPoint(x: identity.candidate.center.x + scene.x, y: identity.candidate.center.y + scene.y) {
                    identity.candidate = try replacingCenter(identity.candidate, moved); locked = identity
                }
                return gap(matches.isEmpty ? "Target lost; no compatible candidate" : "Competing compatible candidates; abstaining")
            }
            if missing {
                recoveryCount += 1
                if recoveryCount < 3 {
                    if let moved = try? VideoPoint(x: identity.candidate.center.x + scene.x, y: identity.candidate.center.y + scene.y) {
                        identity.candidate = try replacingCenter(identity.candidate, moved); locked = identity
                    }
                    return gap("Reacquisition requires three unique matching frames")
                }
            }
            let dt = max(0.001, elapsed)
            identity.velocityX = (candidate.center.x - identity.candidate.center.x - scene.x) / dt
            identity.velocityY = (candidate.center.y - identity.candidate.center.y - scene.y) / dt
            identity.candidate = candidate; identity.last = seconds; locked = identity
            missing = false; recoveryCount = 0
            return decision(identity, kind: .tracked, reason: "Experimental candidate continuity")
        }

        var updated: [Track] = [], used = Set<Int>()
        for candidate in strong {
            let matches = tracks.enumerated().filter { index, track in
                !used.contains(index) && seconds - track.last <= 0.25 && compatible(track.candidate, candidate) &&
                hypot(candidate.center.x - track.candidate.center.x - scene.x,
                      candidate.center.y - track.candidate.center.y - scene.y) <= 0.08
            }.sorted {
                compensatedDistance($0.element.candidate.center, candidate.center, scene) < compensatedDistance($1.element.candidate.center, candidate.center, scene)
            }
            if matches.count > 1, compensatedDistance(matches[0].element.candidate.center, candidate.center, scene) + 0.005 >= compensatedDistance(matches[1].element.candidate.center, candidate.center, scene) {
                continue // Ambiguous tracklet association cannot accumulate initialization evidence.
            }
            if let match = matches.first {
                used.insert(match.offset)
                var track = match.element
                let dx = candidate.center.x - track.candidate.center.x - scene.x
                let dy = candidate.center.y - track.candidate.center.y - scene.y
                let dt = seconds - track.last
                track.streak += 1; track.movement += hypot(dx,dy)
                track.netX += dx; track.netY += dy
                if seconds - track.first > 1.2 {
                    track.streak = 1; track.movement = 0; track.netX = 0; track.netY = 0; track.first = seconds
                }
                track.velocityX = dx / dt; track.velocityY = dy / dt
                track.candidate = candidate; track.last = seconds; updated.append(track)
            } else {
                nextID += 1
                updated.append(Track(id: nextID, candidate: candidate, last: seconds, streak: 1, movement: 0, first: seconds))
            }
        }
        tracks = updated
        let qualified = updated.filter { $0.streak >= 6 && $0.movement >= 0.015 &&
            hypot($0.netX,$0.netY) >= 0.012 && hypot($0.netX,$0.netY) / $0.movement >= 0.6 }
            .sorted { $0.candidate.radius > $1.candidate.radius }
        guard let chosen = qualified.first else { return gap("Insufficient repeated shape and scene-compensated motion") }
        if qualified.count > 1, chosen.candidate.radius < qualified[1].candidate.radius * 1.35 {
            return gap("Multiple plausible moving targets; near side is ambiguous")
        }
        locked = chosen
        return decision(chosen, kind: .automatic, reason: "Experimental unique moving annular candidate; semantic identity unverified")
    }
    private func compatible(_ a: BarCandidate, _ b: BarCandidate) -> Bool {
        let ratio = b.radius / a.radius
        return (0.8...1.25).contains(ratio) && abs(a.aspect - b.aspect) <= 0.12 &&
            abs(a.hubRatio - b.hubRatio) <= 0.06 && zip(a.color,b.color).reduce(0) { $0 + abs($1.0 - $1.1) } / 3 <= 0.12
    }
    private func compensatedDistance(_ a: VideoPoint, _ b: VideoPoint, _ scene: BarSceneShift) -> Double {
        hypot(b.x-a.x-scene.x,b.y-a.y-scene.y)
    }
    private func replacingCenter(_ candidate: BarCandidate, _ center: VideoPoint) throws -> BarCandidate {
        try BarCandidate(center: center, radius: candidate.radius, aspect: candidate.aspect,
            hubRatio: candidate.hubRatio, shapeScore: candidate.shapeScore, color: candidate.color)
    }
    private func gap(_ reason: String) -> BarDecision { BarDecision(point: nil, score: 0, targetID: nil, kind: .lost, reason: reason) }
    private func decision(_ track: Track, kind: VideoTraceSample.Kind, reason: String) -> BarDecision {
        BarDecision(point: track.candidate.center, score: track.candidate.shapeScore,
                    targetID: "candidate-\(track.id)", kind: kind, reason: reason)
    }
}
