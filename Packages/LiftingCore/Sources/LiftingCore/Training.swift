import Foundation

public enum TrainingError: Error, LocalizedError, Equatable, Sendable {
    case invalidReps, invalidWeight, invalidProgression, invalidRanges, invalidIncrement
    case noLoadableTarget, noWarmups, noAttemptPlan, invalidOverride
    public var errorDescription: String? {
        switch self {
        case .invalidReps: return "Use 1–10 whole repetitions."
        case .invalidWeight: return "Enter a positive weight."
        case .invalidProgression: return "Use 1–8 ascending warm-up percentages from 1–99%, with 1–20 reps each."
        case .invalidRanges: return "Use ordered percentage ranges: opener low ≤ high ≤ second low ≤ high, all between 1% and 99%."
        case .invalidIncrement: return "Choose a positive attempt increment."
        case .noLoadableTarget: return "No positive load is available at or below the target with this equipment."
        case .noWarmups: return "No distinct warm-up load is available below the top set. Change the target or inventory."
        case .noAttemptPlan: return "This inventory and increment cannot produce three increasing attempts in those ranges. Adjust the goal, ranges, or equipment."
        case .invalidOverride: return "Manual attempts must be exactly loadable, use the selected increment, and increase opener < second < third."
        }
    }
}

public enum OneRepFormula: String, CaseIterable, Codable, Sendable {
    case epley = "Epley", brzycki = "Brzycki"
    public var equation: String {
        self == .epley ? "weight × (1 + reps ÷ 30)" : "weight × 36 ÷ (37 − reps)"
    }
    // Formula selection/single-rep convention adapted from FineGym fitness-calc (MIT).
    // See THIRD_PARTY_NOTICES.md; our integer mass scaling and 1–10 limit are local.
    public func estimate(weight: Mass, reps: Int) throws -> Mass {
        guard weight > .zero else { throw TrainingError.invalidWeight }
        guard (1...10).contains(reps) else { throw TrainingError.invalidReps }
        if reps == 1 { return weight }
        switch self {
        case .epley: return try weight.scaled(numerator: Int64(30 + reps), denominator: 30)
        case .brzycki: return try weight.scaled(numerator: 36, denominator: Int64(37 - reps))
        }
    }
}

public struct WarmupStep: Hashable, Sendable {
    public var percent: Int
    public var reps: Int
    public init(percent: Int, reps: Int) { self.percent = percent; self.reps = reps }
    public static let standard = [WarmupStep(percent: 40, reps: 5), .init(percent: 55, reps: 4),
                                  .init(percent: 70, reps: 3), .init(percent: 85, reps: 2)]
}
public struct WarmupSet: Sendable {
    public let step: WarmupStep
    public let requested: Mass
    public let load: LoadSolution
}
public struct WarmupPlan: Sendable {
    public let requestedTop: Mass
    public let top: LoadSolution
    public let sets: [WarmupSet]
    public let omittedSteps: Int
}
public enum WarmupPlanner {
    public static func plan(topTarget: Mass, steps: [WarmupStep], equipment: Equipment,
                            inventory: PlateInventory) throws -> WarmupPlan {
        guard topTarget > .zero else { throw TrainingError.invalidWeight }
        guard (1...8).contains(steps.count), steps.allSatisfy({ (1...99).contains($0.percent) && (1...20).contains($0.reps) }),
              zip(steps, steps.dropFirst()).allSatisfy({ $0.0.percent < $0.1.percent }) else { throw TrainingError.invalidProgression }
        let loads = try PlateLoader.achievableLoads(equipment: equipment, inventory: inventory).filter { $0.total > .zero }
        guard let top = loads.last(where: { $0.total <= topTarget }) else { throw TrainingError.noLoadableTarget }
        let available = loads.filter { $0.total < top.total }
        var sets: [WarmupSet] = []
        for step in steps {
            let requested = try top.total.scaled(numerator: Int64(step.percent), denominator: 100)
            // Below-bar percentages can start at the minimum positive load, never above top.
            guard let load = available.last(where: { $0.total <= requested }) ?? available.first else { continue }
            if let previous = sets.last, load.total <= previous.load.total { continue }
            sets.append(WarmupSet(step: step, requested: requested, load: load))
        }
        guard !sets.isEmpty else { throw TrainingError.noWarmups }
        return WarmupPlan(requestedTop: topTarget, top: top, sets: sets, omittedSteps: steps.count - sets.count)
    }
}

public struct AttemptRanges: Hashable, Sendable {
    public let openerLow: Int, openerHigh: Int, secondLow: Int, secondHigh: Int
    public init(openerLow: Int = 80, openerHigh: Int = 90, secondLow: Int = 90, secondHigh: Int = 97) throws {
        guard openerLow > 0, openerLow <= openerHigh, openerHigh <= secondLow,
              secondLow <= secondHigh, secondHigh < 100 else { throw TrainingError.invalidRanges }
        self.openerLow = openerLow; self.openerHigh = openerHigh
        self.secondLow = secondLow; self.secondHigh = secondHigh
    }
}
public struct AttemptPlan: Sendable {
    public let goal: Mass
    public let opener: LoadSolution, second: LoadSolution, third: LoadSolution
    public let openerRange: [LoadSolution], secondRange: [LoadSolution]
}
public enum AttemptPlanner {
    public static func plan(thirdGoal: Mass, increment: Mass, ranges: AttemptRanges,
                            equipment: Equipment, inventory: PlateInventory,
                            openerOverride: Mass? = nil, secondOverride: Mass? = nil) throws -> AttemptPlan {
        guard thirdGoal > .zero else { throw TrainingError.invalidWeight }
        guard increment > .zero else { throw TrainingError.invalidIncrement }
        let loads = try PlateLoader.achievableLoads(equipment: equipment, inventory: inventory)
            .filter { $0.total > .zero && $0.total.nanograms % increment.nanograms == 0 }
        guard let third = loads.last(where: { $0.total <= thirdGoal }) else { throw TrainingError.noLoadableTarget }
        func inRange(_ low: Int, _ high: Int) throws -> [LoadSolution] {
            let minimum = try third.total.scaled(numerator: Int64(low), denominator: 100)
            let maximum = try third.total.scaled(numerator: Int64(high), denominator: 100)
            return loads.filter { $0.total >= minimum && $0.total <= maximum && $0.total < third.total }
        }
        let openerRange = try inRange(ranges.openerLow, ranges.openerHigh)
        let secondRange = try inRange(ranges.secondLow, ranges.secondHigh)
        func nearest(_ candidates: [LoadSolution], low: Int, high: Int) throws -> LoadSolution? {
            let midpoint = try third.total.scaled(numerator: Int64(low + high), denominator: 200)
            return candidates.min {
                let left = abs($0.total.nanograms - midpoint.nanograms), right = abs($1.total.nanograms - midpoint.nanograms)
                return left == right ? $0.total < $1.total : left < right
            }
        }
        let opener: LoadSolution
        if let override = openerOverride {
            guard let load = loads.first(where: { $0.total == override && $0.total < third.total }) else { throw TrainingError.invalidOverride }
            opener = load
        } else {
            // An opener must leave an eligible higher second, including a manual override.
            let possible = openerRange.filter { first in
                if let secondOverride { return first.total < secondOverride && secondOverride < third.total }
                return secondRange.contains { $0.total > first.total }
            }
            guard let load = try nearest(possible, low: ranges.openerLow, high: ranges.openerHigh) else { throw TrainingError.noAttemptPlan }
            opener = load
        }
        let second: LoadSolution
        if let override = secondOverride {
            guard let load = loads.first(where: { $0.total == override && $0.total > opener.total && $0.total < third.total }) else { throw TrainingError.invalidOverride }
            second = load
        } else {
            guard let load = try nearest(secondRange.filter { $0.total > opener.total }, low: ranges.secondLow, high: ranges.secondHigh) else { throw TrainingError.noAttemptPlan }
            second = load
        }
        return AttemptPlan(goal: thirdGoal, opener: opener, second: second, third: third,
                           openerRange: openerRange, secondRange: secondRange)
    }
}
