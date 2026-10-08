import XCTest
@testable import LiftingCore

final class PlateLoaderTests: XCTestCase {
    private struct Fixture: Decodable {
        let name: String
        let target: String
        let targetUnit: WeightUnit
        let bar: String
        let barUnit: WeightUnit
        let collar: String
        let inventoryUnit: WeightUnit
        let plates: [[Int64]]
        let closest: String
        let lower: String?
        let upper: String?
        let resultUnit: WeightUnit
        let counts: [[Int64]]
    }

    func testReferenceFixturesAndReverseRoundTrip() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "loading", withExtension: "json", subdirectory: "Fixtures"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        for fixture in fixtures {
            let equipment = Equipment(bar: try amount(fixture.bar, fixture.barUnit),
                                      collarEach: try amount(fixture.collar, fixture.barUnit))
            let inventory = try PlateInventory(unit: fixture.inventoryUnit, entries: fixture.plates.map {
                try PlateEntry(milliUnits: $0[0], availablePairs: Int($0[1]))
            })
            let result = try PlateLoader.load(target: amount(fixture.target, fixture.targetUnit), equipment: equipment, inventory: inventory)
            XCTAssertEqual(result.closest.total, try amount(fixture.closest, fixture.resultUnit), fixture.name)
            XCTAssertEqual(result.lower?.total, try fixture.lower.map { try amount($0, fixture.resultUnit) }, fixture.name)
            XCTAssertEqual(result.upper?.total, try fixture.upper.map { try amount($0, fixture.resultUnit) }, fixture.name)
            let expected = Dictionary(uniqueKeysWithValues: fixture.counts.map { ($0[0], Int($0[1])) })
            let actual = Dictionary(uniqueKeysWithValues: result.closest.plates.map { ($0.weight.milliUnits, $0.perSide) })
            XCTAssertEqual(actual, expected, fixture.name)
            let reverse = try PlateLoader.reverse(equipment: equipment, inventory: inventory, counts: actual)
            XCTAssertEqual(reverse, result.closest, fixture.name)
        }
    }

    func testExactUnitConversionAndInputBoundaries() throws {
        XCTAssertEqual(try amount("1", .pounds).nanograms, 453_592_370_000)
        XCTAssertEqual(try amount("0.001", .pounds).nanograms, 453_592_370)
        XCTAssertEqual(try amount(".5", .kilograms), try amount("0.500", .kilograms))
        XCTAssertEqual(try amount(" 45. ", .pounds), try amount("45", .pounds))
        for input in ["", ".", "-1", "NaN", "inf", "1,000", "1e2", "1.2.3", "10001", "9223372036854775807"] {
            XCTAssertThrowsError(try amount(input, .kilograms), input)
        }
        XCTAssertThrowsError(try amount("1.0001", .pounds)) {
            XCTAssertEqual($0 as? LoadingError, .tooManyDecimals)
        }
        XCTAssertThrowsError(try Mass(nanograms: -1))
        XCTAssertThrowsError(try amount("10", .kilograms).multiplied(by: Int.max))
    }

    func testInvalidInventoriesAndSelections() throws {
        XCTAssertThrowsError(try PlateEntry(milliUnits: 0, availablePairs: 1))
        XCTAssertThrowsError(try PlateEntry(milliUnits: 5_000, availablePairs: -1))
        XCTAssertThrowsError(try PlateEntry(milliUnits: 5_000, availablePairs: 41))
        let plate = try PlateEntry(milliUnits: 5_000, availablePairs: 1)
        XCTAssertThrowsError(try PlateInventory(unit: .kilograms, entries: []))
        XCTAssertThrowsError(try PlateInventory(unit: .kilograms, entries: [plate, plate]))
        XCTAssertThrowsError(try PlateInventory(unit: .kilograms, entries: [
            PlateEntry(milliUnits: 5_000, availablePairs: 40), PlateEntry(milliUnits: 1_000, availablePairs: 1)
        ]))
        let inventory = try PlateInventory(unit: .kilograms, entries: [plate])
        let equipment = Equipment(bar: try amount("20", .kilograms))
        let invalidSelections: [[Int64: Int]] = [[5_000: 2], [5_000: -1], [2_500: 1], [2_500: 0]]
        for counts in invalidSelections {
            XCTAssertThrowsError(try PlateLoader.reverse(equipment: equipment, inventory: inventory, counts: counts))
        }
        XCTAssertThrowsError(try PlateLoader.load(target: amount("30", .kilograms), equipment: equipment, inventory: inventory, stateLimit: 1)) {
            XCTAssertEqual($0 as? LoadingError, .inventoryTooComplex)
        }
    }

    func testDecodingCannotBypassValidation() {
        XCTAssertThrowsError(try JSONDecoder().decode(Mass.self, from: Data("{\"nanograms\":-1}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(WeightAmount.self, from: Data("{\"milliUnits\":-1,\"unit\":\"kg\"}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(PlateEntry.self, from: Data("{\"milliUnits\":0,\"availablePairs\":1}".utf8)))
    }

    /// Enumerates complete count vectors independently of the solver's merged reachable sums.
    func testSmallInventoriesAgainstExhaustiveOracle() throws {
        var seed: UInt64 = 42
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int((seed >> 32) % UInt64(bound))
        }
        for index in 0..<120 {
            let unit: WeightUnit = index.isMultiple(of: 2) ? .kilograms : .pounds
            let sizes = Set((0..<4).map { _ in Int64(next(15) + 1) * 250 }).sorted(by: >)
            let entries = try sizes.map { try PlateEntry(milliUnits: $0, availablePairs: next(3)) }
            let inventory = try PlateInventory(unit: unit, entries: entries)
            let equipment = Equipment(bar: try amount("20", .kilograms), collarEach: try amount("0.5", .kilograms))
            let target = try WeightAmount(milliUnits: Int64(next(100_000)), unit: unit).mass
            var vectors: [[Int]] = [[]]
            for entry in entries {
                vectors = vectors.flatMap { prefix in (0...entry.availablePairs).map { prefix + [$0] } }
            }
            let all: [(Mass, [Int])] = try vectors.map { counts in
                var total = try equipment.baseMass
                for (entry, count) in zip(entries, counts) {
                    total = try total.adding(entry.weight(in: unit).mass.multiplied(by: count * 2))
                }
                return (total, counts)
            }
            let sorted = all.sorted { left, right in
                let leftDistance = abs(left.0.nanograms - target.nanograms)
                let rightDistance = abs(right.0.nanograms - target.nanograms)
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                if left.0 != right.0 { return left.0 < right.0 }
                let leftCount = left.1.reduce(0, +), rightCount = right.1.reduce(0, +)
                if leftCount != rightCount { return leftCount < rightCount }
                for (a, b) in zip(left.1, right.1) where a != b { return a > b }
                return false
            }
            let expected = try XCTUnwrap(sorted.first)
            let result = try PlateLoader.load(target: target, equipment: equipment, inventory: inventory)
            XCTAssertEqual(result.closest.total, expected.0, "Inventory \(index)")
            let counts = Dictionary(uniqueKeysWithValues: result.closest.plates.map { ($0.weight.milliUnits, $0.perSide) })
            XCTAssertEqual(entries.map { counts[$0.milliUnits, default: 0] }, expected.1, "Inventory \(index)")
            XCTAssertEqual(result.lower?.total, all.map(\.0).filter { $0 <= target }.max())
            XCTAssertEqual(result.upper?.total, all.map(\.0).filter { $0 >= target }.min())
        }
    }

    private func amount(_ text: String, _ unit: WeightUnit) throws -> Mass {
        try WeightAmount.parse(text, unit: unit).mass
    }
}
