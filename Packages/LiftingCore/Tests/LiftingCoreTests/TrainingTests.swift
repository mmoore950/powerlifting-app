import XCTest
@testable import LiftingCore

final class TrainingTests: XCTestCase {
    private func mass(_ value: String, _ unit: WeightUnit = .kilograms) throws -> Mass {
        try WeightAmount.parse(value, unit: unit).mass
    }
    private var bar: Equipment { Equipment(bar: try! mass("20")) }

    func testOneRepIdentityKnownValuesAndUnitIndependence() throws {
        for formula in OneRepFormula.allCases {
            let performed = try mass("225", .pounds)
            XCTAssertEqual(try formula.estimate(weight: performed, reps: 1), performed)
            XCTAssertEqual(try formula.estimate(weight: mass("100"), reps: 10).value(in: .kilograms), 133.333333333333, accuracy: 1e-9)
        }
        XCTAssertEqual(try OneRepFormula.epley.estimate(weight: mass("100"), reps: 5).value(in: .kilograms), 116.666666666666, accuracy: 1e-9)
        XCTAssertEqual(try OneRepFormula.brzycki.estimate(weight: mass("100"), reps: 5), try mass("112.5"))
        XCTAssertEqual(try OneRepFormula.epley.estimate(weight: mass("225", .pounds), reps: 3), try mass("247.5", .pounds))
        for formula in OneRepFormula.allCases {
            for reps in [0, -1, 11, 37, Int.max] { XCTAssertThrowsError(try formula.estimate(weight: mass("100"), reps: reps)) }
            XCTAssertThrowsError(try formula.estimate(weight: .zero, reps: 5))
            XCTAssertThrowsError(try formula.estimate(weight: Mass(nanograms: 1_000_000_000_000_000_000), reps: 10))
        }
    }

    func testWarmupKnownProgressionAndUnreachableTop() throws {
        let plan = try WarmupPlanner.plan(topTarget: mass("140.1"), steps: WarmupStep.standard,
                                           equipment: bar, inventory: .standard(.kilograms))
        XCTAssertEqual(plan.top.total, try mass("140"))
        XCTAssertEqual(plan.sets.map { $0.load.total.value(in: .kilograms) }, [56, 77, 98, 119])
        XCTAssertEqual(plan.omittedSteps, 0)
        for set in plan.sets {
            let counts = Dictionary(uniqueKeysWithValues: set.load.plates.map { ($0.weight.milliUnits, $0.perSide) })
            XCTAssertEqual(try PlateLoader.reverse(equipment: bar, inventory: .standard(.kilograms), counts: counts), set.load)
        }
    }

    func testWarmupsSkipDuplicateBarLoadsAndNeverExceedTop() throws {
        let plan = try WarmupPlanner.plan(topTarget: mass("25"), steps: WarmupStep.standard,
                                           equipment: bar, inventory: .standard(.kilograms))
        XCTAssertEqual(plan.sets.map { $0.load.total.value(in: .kilograms) }, [20, 21])
        XCTAssertEqual(plan.omittedSteps, 2)
        for target in ["20", "10", "0"] {
            XCTAssertThrowsError(try WarmupPlanner.plan(topTarget: mass(target), steps: WarmupStep.standard, equipment: bar, inventory: .standard(.kilograms)))
        }
        for steps in [[WarmupStep(percent: 0, reps: 5)], [.init(percent: 50, reps: 0)],
                      [.init(percent: 100, reps: 1)], [.init(percent: 70, reps: 3), .init(percent: 40, reps: 5)]] {
            XCTAssertThrowsError(try WarmupPlanner.plan(topTarget: mass("140"), steps: steps, equipment: bar, inventory: .standard(.kilograms)))
        }
        for target in stride(from: 25, through: 225, by: 10) {
            let plan = try WarmupPlanner.plan(topTarget: mass(String(target)), steps: WarmupStep.standard, equipment: bar, inventory: .standard(.kilograms))
            XCTAssertTrue(plan.sets.allSatisfy { $0.load.total > .zero && $0.load.total < plan.top.total })
            XCTAssertTrue(zip(plan.sets, plan.sets.dropFirst()).allSatisfy { $0.0.load.total < $0.1.load.total })
        }
    }

    func testAttemptPlanUsesLoadableIncrementAndOrderedWeights() throws {
        let plan = try AttemptPlanner.plan(thirdGoal: mass("201"), increment: mass("2.5"), ranges: AttemptRanges(), equipment: bar, inventory: .standard(.kilograms))
        XCTAssertEqual(plan.opener.total, try mass("170"))
        XCTAssertEqual(plan.second.total, try mass("187.5"))
        XCTAssertEqual(plan.third.total, try mass("200"))
        for load in [plan.opener, plan.second, plan.third] {
            XCTAssertEqual(load.total.nanograms % (try mass("2.5").nanograms), 0)
            let counts = Dictionary(uniqueKeysWithValues: load.plates.map { ($0.weight.milliUnits, $0.perSide) })
            XCTAssertEqual(try PlateLoader.reverse(equipment: bar, inventory: .standard(.kilograms), counts: counts).total, load.total)
        }
        let manual = try AttemptPlanner.plan(thirdGoal: mass("200"), increment: mass("2.5"), ranges: AttemptRanges(), equipment: bar, inventory: .standard(.kilograms), openerOverride: mass("145"), secondOverride: mass("197.5"))
        XCTAssertEqual(manual.opener.total, try mass("145"))
        XCTAssertEqual(manual.second.total, try mass("197.5"))
        for (opener, second) in [("173.1", "190"), ("190", "180"), ("180", "200")] {
            XCTAssertThrowsError(try AttemptPlanner.plan(thirdGoal: mass("200"), increment: mass("2.5"), ranges: AttemptRanges(), equipment: bar, inventory: .standard(.kilograms), openerOverride: mass(opener), secondOverride: mass(second)))
        }
        XCTAssertThrowsError(try AttemptRanges(openerLow: 95, openerHigh: 90))
        XCTAssertThrowsError(try AttemptRanges(secondHigh: 100))
        XCTAssertThrowsError(try AttemptPlanner.plan(thirdGoal: mass("200"), increment: .zero, ranges: AttemptRanges(), equipment: bar, inventory: .standard(.kilograms)))
        let limited = try PlateInventory(unit: .kilograms, entries: [PlateEntry(milliUnits: 5_000, availablePairs: 1)])
        XCTAssertThrowsError(try AttemptPlanner.plan(thirdGoal: mass("30"), increment: mass("2.5"), ranges: AttemptRanges(), equipment: bar, inventory: limited))
    }
}
