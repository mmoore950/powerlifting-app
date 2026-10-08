import Foundation

public struct AppPreferences: Codable, Hashable, Sendable {
    public let equipment: Equipment
    public let kilogramInventory: PlateInventory
    public let poundInventory: PlateInventory
    public let displayUnit: WeightUnit
    public let plateUnit: WeightUnit
    public let target: Mass

    public init(equipment: Equipment, kilogramInventory: PlateInventory, poundInventory: PlateInventory,
                displayUnit: WeightUnit, plateUnit: WeightUnit, target: Mass) throws {
        guard kilogramInventory.unit == .kilograms, poundInventory.unit == .pounds else { throw LoadingError.invalidInventory }
        _ = try equipment.baseMass
        // Validate equipment plus maximum finite load without running the combinatorial search.
        for inventory in [kilogramInventory, poundInventory] {
            _ = try PlateLoader.reverse(equipment: equipment, inventory: inventory,
                                        counts: Dictionary(uniqueKeysWithValues: inventory.entries.map { ($0.milliUnits, $0.availablePairs) }))
        }
        self.equipment = equipment; self.kilogramInventory = kilogramInventory; self.poundInventory = poundInventory
        self.displayUnit = displayUnit; self.plateUnit = plateUnit; self.target = target
    }
    public static var defaults: AppPreferences {
        try! AppPreferences(equipment: Equipment(bar: WeightAmount(milliUnits: 45_000, unit: .pounds).mass),
                            kilogramInventory: .standard(.kilograms), poundInventory: .standard(.pounds),
                            displayUnit: .pounds, plateUnit: .pounds,
                            target: WeightAmount(milliUnits: 225_000, unit: .pounds).mass)
    }
    private enum CodingKeys: String, CodingKey { case equipment, kilogramInventory, poundInventory, displayUnit, plateUnit, target }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(equipment: values.decode(Equipment.self, forKey: .equipment),
                      kilogramInventory: values.decode(PlateInventory.self, forKey: .kilogramInventory),
                      poundInventory: values.decode(PlateInventory.self, forKey: .poundInventory),
                      displayUnit: values.decode(WeightUnit.self, forKey: .displayUnit),
                      plateUnit: values.decode(WeightUnit.self, forKey: .plateUnit),
                      target: values.decode(Mass.self, forKey: .target))
    }
}

public enum PreferencesRecoveryKind: String, Sendable { case fresh, restored, migrated, reset }
public struct PreferencesRecovery: Sendable {
    public let preferences: AppPreferences
    public let kind: PreferencesRecoveryKind
    public let notice: String?
}
public enum PreferencesCodec {
    public static let schemaVersion = 1
    public static let maximumBytes = 100_000
    private struct Version: Decodable { let schemaVersion: Int }
    private struct Envelope: Codable { let schemaVersion: Int; let preferences: AppPreferences }
    // Explicit documented legacy contract, used for migration tests; no previous shipped app exists.
    private struct Legacy: Decodable {
        let schemaVersion: Int
        let bar: WeightAmount
        let collarEach: WeightAmount
        let kilogramInventory: PlateInventory
        let poundInventory: PlateInventory
        let displayUnit: WeightUnit
        let plateUnit: WeightUnit
        let target: WeightAmount
    }
    public static func encode(_ preferences: AppPreferences) throws -> Data {
        // Revalidate mutable Equipment fields before writing.
        let valid = try AppPreferences(equipment: preferences.equipment, kilogramInventory: preferences.kilogramInventory,
                                       poundInventory: preferences.poundInventory, displayUnit: preferences.displayUnit,
                                       plateUnit: preferences.plateUnit, target: preferences.target)
        let data = try JSONEncoder().encode(Envelope(schemaVersion: schemaVersion, preferences: valid))
        guard data.count <= maximumBytes else { throw LoadingError.invalidInventory }
        return data
    }
    public static func recover(_ data: Data?) -> PreferencesRecovery {
        guard let data else { return PreferencesRecovery(preferences: .defaults, kind: .fresh, notice: nil) }
        do {
            guard data.count <= maximumBytes else { throw LoadingError.invalidInventory }
            let decoder = JSONDecoder()
            let version = try decoder.decode(Version.self, from: data).schemaVersion
            switch version {
            case schemaVersion:
                let envelope = try decoder.decode(Envelope.self, from: data)
                return PreferencesRecovery(preferences: envelope.preferences, kind: .restored, notice: nil)
            case 0:
                let old = try decoder.decode(Legacy.self, from: data)
                let preferences = try AppPreferences(equipment: Equipment(bar: old.bar.mass, collarEach: old.collarEach.mass),
                                                     kilogramInventory: old.kilogramInventory, poundInventory: old.poundInventory,
                                                     displayUnit: old.displayUnit, plateUnit: old.plateUnit, target: old.target.mass)
                return PreferencesRecovery(preferences: preferences, kind: .migrated, notice: "Saved equipment was updated to the current format.")
            default:
                return PreferencesRecovery(preferences: .defaults, kind: .reset, notice: "Saved settings use an unsupported format. Starter equipment is active; the original data was preserved.")
            }
        } catch {
            return PreferencesRecovery(preferences: .defaults, kind: .reset, notice: "Saved settings could not be read safely. Starter equipment is active; the original data was preserved.")
        }
    }
}
