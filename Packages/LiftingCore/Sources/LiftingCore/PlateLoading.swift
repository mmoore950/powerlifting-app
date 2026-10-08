import Foundation

public struct Equipment: Hashable, Codable, Sendable {
    public var bar: Mass
    /// Mass of ONE collar. There are two collars in every total.
    public var collarEach: Mass
    public init(bar: Mass, collarEach: Mass = .zero) {
        self.bar = bar
        self.collarEach = collarEach
    }
    public var baseMass: Mass { get throws { try bar.adding(collarEach.multiplied(by: 2)) } }
}

public struct PlateEntry: Hashable, Codable, Identifiable, Sendable {
    public let milliUnits: Int64
    public let availablePairs: Int
    public var id: Int64 { milliUnits }

    public init(milliUnits: Int64, availablePairs: Int) throws {
        guard (1...10_000_000).contains(milliUnits), (0...40).contains(availablePairs) else {
            throw LoadingError.invalidInventory
        }
        self.milliUnits = milliUnits
        self.availablePairs = availablePairs
    }

    public func weight(in unit: WeightUnit) -> WeightAmount {
        // Validated at construction and again before using decoded inventories.
        try! WeightAmount(milliUnits: milliUnits, unit: unit)
    }

    private enum CodingKeys: String, CodingKey { case milliUnits, availablePairs }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(milliUnits: values.decode(Int64.self, forKey: .milliUnits),
                      availablePairs: values.decode(Int.self, forKey: .availablePairs))
    }
}

public struct PlateInventory: Hashable, Codable, Sendable {
    public let unit: WeightUnit
    public let entries: [PlateEntry]

    public init(unit: WeightUnit, entries: [PlateEntry]) throws {
        guard (1...16).contains(entries.count), entries.reduce(0, { $0 + $1.availablePairs }) <= 40 else {
            throw LoadingError.invalidInventory
        }
        guard Set(entries.map(\.milliUnits)).count == entries.count else { throw LoadingError.duplicatePlate }
        self.unit = unit
        self.entries = entries.sorted { $0.milliUnits > $1.milliUnits }
    }

    public static func standard(_ unit: WeightUnit) -> PlateInventory {
        let sizes: [(Int64, Int)] = unit == .kilograms
            ? [(25_000, 4), (20_000, 4), (15_000, 2), (10_000, 2), (5_000, 2),
               (2_500, 2), (1_250, 2), (500, 2), (250, 2)]
            : [(45_000, 4), (35_000, 2), (25_000, 2), (10_000, 2), (5_000, 2),
               (2_500, 2), (1_250, 2), (500, 2), (250, 2)]
        return try! PlateInventory(unit: unit, entries: sizes.map {
            try PlateEntry(milliUnits: $0.0, availablePairs: $0.1)
        })
    }

    private enum CodingKeys: String, CodingKey { case unit, entries }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(unit: values.decode(WeightUnit.self, forKey: .unit),
                      entries: values.decode([PlateEntry].self, forKey: .entries))
    }
}

public struct PlateCount: Hashable, Sendable {
    public let weight: WeightAmount
    /// Plates on ONE side; identical plates go on the other side.
    public let perSide: Int
}

public struct LoadSolution: Hashable, Sendable {
    public let total: Mass
    public let plates: [PlateCount]
    public var platePairs: Int { plates.reduce(0) { $0 + $1.perSide } }
}

public struct LoadingResult: Sendable {
    public let requested: Mass
    public let lower: LoadSolution?
    public let upper: LoadSolution?
    public let closest: LoadSolution
    public var isExact: Bool { closest.total == requested }
}

public enum PlateLoader {
    public static let maximumReachableStates = 50_000

    /// Bounded knapsack over the entire finite inventory. This is not a greedy loader.
    /// For equal totals choose the fewest plates, then favor larger denominations.
    public static func load(target: Mass, equipment: Equipment, inventory: PlateInventory,
                            stateLimit: Int = maximumReachableStates) throws -> LoadingResult {
        let solutions = try achievableLoads(equipment: equipment, inventory: inventory, stateLimit: stateLimit)
        let lower = solutions.last { $0.total <= target }
        let upper = solutions.first { $0.total >= target }
        let closest: LoadSolution
        switch (lower, upper) {
        case let (.some(low), .some(high)):
            closest = target.nanograms - low.total.nanograms <= high.total.nanograms - target.nanograms ? low : high
        case let (.some(low), .none): closest = low
        case let (.none, .some(high)): closest = high
        case (.none, .none): throw LoadingError.invalidInventory
        }
        return LoadingResult(requested: target, lower: lower, upper: upper, closest: closest)
    }

    /// Shared sorted unique loads for calculators; the inventory search runs once per plan.
    public static func achievableLoads(equipment: Equipment, inventory: PlateInventory,
                                       stateLimit: Int = maximumReachableStates) throws -> [LoadSolution] {
        guard stateLimit > 0 else { throw LoadingError.inventoryTooComplex }
        let base = try equipment.baseMass
        let entries = inventory.entries
        var reachable: [Int64: Combination] = [0: Combination(counts: [], pairs: 0)]
        for entry in entries {
            try Task.checkCancellation()
            var next: [Int64: Combination] = [:]
            var visited = 0
            for (sum, previous) in reachable {
                visited += 1
                if visited.isMultiple(of: 256) { try Task.checkCancellation() }
                for count in 0...entry.availablePairs {
                    let newSum = sum + entry.milliUnits * Int64(count)
                    let candidate = Combination(counts: previous.counts + [count], pairs: previous.pairs + count)
                    if let existing = next[newSum] {
                        if candidate.preferred(to: existing) { next[newSum] = candidate }
                    } else {
                        guard next.count < stateLimit else { throw LoadingError.inventoryTooComplex }
                        next[newSum] = candidate
                    }
                }
            }
            reachable = next
        }

        return try reachable.map { sum, combination in
            try Task.checkCancellation()
            let pairNanograms = sum * inventory.unit.nanogramsPerMilliUnit * 2
            let total = try base.adding(Mass(nanograms: pairNanograms))
            return LoadSolution(total: total, plates: zip(entries, combination.counts).compactMap {
                $0.1 == 0 ? nil : PlateCount(weight: $0.0.weight(in: inventory.unit), perSide: $0.1)
            })
        }.sorted { $0.total < $1.total }
    }

    public static func reverse(equipment: Equipment, inventory: PlateInventory,
                               counts: [Int64: Int]) throws -> LoadSolution {
        guard counts.allSatisfy({ key, count in
            guard let entry = inventory.entries.first(where: { $0.milliUnits == key }) else { return false }
            return count >= 0 && count <= entry.availablePairs
        }) else { throw LoadingError.invalidSelection }
        var total = try equipment.baseMass
        var plates: [PlateCount] = []
        for entry in inventory.entries {
            let count = counts[entry.milliUnits, default: 0]
            if count > 0 {
                let weight = entry.weight(in: inventory.unit)
                total = try total.adding(weight.mass.multiplied(by: count * 2))
                plates.append(PlateCount(weight: weight, perSide: count))
            }
        }
        return LoadSolution(total: total, plates: plates)
    }

    private struct Combination {
        let counts: [Int]
        let pairs: Int
        func preferred(to other: Combination) -> Bool {
            if pairs != other.pairs { return pairs < other.pairs }
            for (left, right) in zip(counts, other.counts) where left != right { return left > right }
            return false
        }
    }
}
