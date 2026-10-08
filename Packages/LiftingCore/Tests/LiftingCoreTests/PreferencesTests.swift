import XCTest
@testable import LiftingCore

final class PreferencesTests: XCTestCase {
    func testRoundTripKeepsIndependentUnitsAndExactMass() throws {
        let value = try AppPreferences(equipment: Equipment(bar: WeightAmount(milliUnits: 45_000, unit: .pounds).mass,
                                                           collarEach: WeightAmount(milliUnits: 2_500, unit: .kilograms).mass),
                                       kilogramInventory: .standard(.kilograms), poundInventory: .standard(.pounds),
                                       displayUnit: .kilograms, plateUnit: .pounds,
                                       target: WeightAmount(milliUnits: 225_000, unit: .pounds).mass)
        let recovery = PreferencesCodec.recover(try PreferencesCodec.encode(value))
        XCTAssertEqual(recovery.kind, .restored)
        XCTAssertEqual(recovery.preferences, value)
        XCTAssertEqual(recovery.preferences.target.nanograms, 102_058_283_250_000)
    }

    func testCorruptUnknownAndInvalidDecodedDataRecoverSafely() throws {
        XCTAssertEqual(PreferencesCodec.recover(nil).kind, .fresh)
        for text in ["not json", "{}", "{\"schemaVersion\":99}"] {
            let recovery = PreferencesCodec.recover(Data(text.utf8))
            XCTAssertEqual(recovery.kind, .reset)
            XCTAssertEqual(recovery.preferences, .defaults)
            XCTAssertNotNil(recovery.notice)
        }
        XCTAssertEqual(PreferencesCodec.recover(Data(repeating: 0, count: PreferencesCodec.maximumBytes + 1)).kind, .reset)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: PreferencesCodec.encode(.defaults)) as? [String: Any])
        var preferences = try XCTUnwrap(envelope["preferences"] as? [String: Any])
        var inventory = try XCTUnwrap(preferences["kilogramInventory"] as? [String: Any])
        inventory["unit"] = "lb"
        preferences["kilogramInventory"] = inventory
        envelope["preferences"] = preferences
        XCTAssertEqual(PreferencesCodec.recover(try JSONSerialization.data(withJSONObject: envelope)).kind, .reset)
    }

    func testLegacyNominalUnitsMigrateToCanonicalPhysicalMass() throws {
        let old: [String: Any] = [
            "schemaVersion": 0,
            "bar": ["milliUnits": 45_000, "unit": "lb"],
            "collarEach": ["milliUnits": 2_500, "unit": "kg"],
            "kilogramInventory": ["unit": "kg", "entries": [["milliUnits": 25_000, "availablePairs": 2]]],
            "poundInventory": ["unit": "lb", "entries": [["milliUnits": 45_000, "availablePairs": 2]]],
            "displayUnit": "kg", "plateUnit": "lb",
            "target": ["milliUnits": 225_000, "unit": "lb"]
        ]
        let recovery = PreferencesCodec.recover(try JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(recovery.kind, .migrated)
        XCTAssertEqual(recovery.preferences.equipment.bar.nanograms, 20_411_656_650_000)
        XCTAssertEqual(recovery.preferences.equipment.collarEach.nanograms, 2_500_000_000_000)
        XCTAssertEqual(recovery.preferences.target.nanograms, 102_058_283_250_000)
        XCTAssertEqual(recovery.preferences.displayUnit, .kilograms)
        XCTAssertEqual(recovery.preferences.plateUnit, .pounds)
        XCTAssertEqual(PreferencesCodec.recover(try PreferencesCodec.encode(recovery.preferences)).kind, .restored)
    }
}
