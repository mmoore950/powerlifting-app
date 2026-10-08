import Foundation

public enum WeightUnit: String, CaseIterable, Codable, Sendable {
    case kilograms = "kg"
    case pounds = "lb"

    public var symbol: String { rawValue }
    public var other: WeightUnit { self == .kilograms ? .pounds : .kilograms }
    // The international pound is exactly 0.45359237 kg.
    public var nanogramsPerUnit: Int64 {
        self == .kilograms ? 1_000_000_000_000 : 453_592_370_000
    }
    var nanogramsPerMilliUnit: Int64 { nanogramsPerUnit / 1_000 }
}

public enum LoadingError: Error, Equatable, LocalizedError, Sendable {
    case invalidWeight
    case tooManyDecimals
    case weightOutOfRange
    case invalidInventory
    case duplicatePlate
    case invalidSelection
    case inventoryTooComplex

    public var errorDescription: String? {
        switch self {
        case .invalidWeight: return "Enter a nonnegative weight using numbers and one decimal separator."
        case .tooManyDecimals: return "Use no more than three decimal places."
        case .weightOutOfRange: return "This weight is outside the supported range."
        case .invalidInventory: return "Use 1–16 different positive plate sizes and no more than 40 pairs in total."
        case .duplicatePlate: return "Each plate size should appear once. Adjust its available pairs instead."
        case .invalidSelection: return "The selected load exceeds the available pairs or contains an unknown plate."
        case .inventoryTooComplex: return "This custom inventory has too many combinations. Reduce the plate sizes or available pairs."
        }
    }
}

/// Physical mass is the source of truth; floating point is used only for display.
public struct Mass: Hashable, Comparable, Codable, Sendable {
    public let nanograms: Int64
    public static let zero = Mass(unchecked: 0)
    private static let maximum: Int64 = 1_000_000_000_000_000_000

    public init(nanograms: Int64) throws {
        guard (0...Self.maximum).contains(nanograms) else { throw LoadingError.weightOutOfRange }
        self.nanograms = nanograms
    }

    fileprivate init(unchecked nanograms: Int64) { self.nanograms = nanograms }
    public static func < (lhs: Mass, rhs: Mass) -> Bool { lhs.nanograms < rhs.nanograms }

    public func adding(_ other: Mass) throws -> Mass {
        let (value, overflow) = nanograms.addingReportingOverflow(other.nanograms)
        guard !overflow else { throw LoadingError.weightOutOfRange }
        return try Mass(nanograms: value)
    }

    public func multiplied(by count: Int) throws -> Mass {
        guard count >= 0 else { throw LoadingError.invalidSelection }
        let (value, overflow) = nanograms.multipliedReportingOverflow(by: Int64(count))
        guard !overflow else { throw LoadingError.weightOutOfRange }
        return try Mass(nanograms: value)
    }

    /// Rational scaling, rounded down to a nanogram without floating-point intermediates.
    public func scaled(numerator: Int64, denominator: Int64) throws -> Mass {
        guard (0...10_000).contains(numerator), (1...10_000).contains(denominator) else {
            throw LoadingError.weightOutOfRange
        }
        let (whole, overflow) = (nanograms / denominator).multipliedReportingOverflow(by: numerator)
        guard !overflow else { throw LoadingError.weightOutOfRange }
        let remainder = (nanograms % denominator) * numerator / denominator
        let (total, sumOverflow) = whole.addingReportingOverflow(remainder)
        guard !sumOverflow else { throw LoadingError.weightOutOfRange }
        return try Mass(nanograms: total)
    }

    public func value(in unit: WeightUnit) -> Double {
        Double(nanograms) / Double(unit.nanogramsPerUnit)
    }

    public func formatted(in unit: WeightUnit, fractionDigits: Int = 3,
                          locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits
        let amount = Decimal(nanograms) / Decimal(unit.nanogramsPerUnit)
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "—"
    }

    private enum CodingKeys: String, CodingKey { case nanograms }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(nanograms: values.decode(Int64.self, forKey: .nanograms))
    }
}

/// Exact input with up to three decimal places in its original unit.
public struct WeightAmount: Hashable, Codable, Sendable {
    public let milliUnits: Int64
    public let unit: WeightUnit
    public var mass: Mass { Mass(unchecked: milliUnits * unit.nanogramsPerMilliUnit) }

    public init(milliUnits: Int64, unit: WeightUnit) throws {
        guard (0...10_000_000).contains(milliUnits) else { throw LoadingError.weightOutOfRange }
        self.milliUnits = milliUnits
        self.unit = unit
    }

    public static func parse(_ text: String, unit: WeightUnit) throws -> WeightAmount {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard !cleaned.isEmpty, parts.count <= 2,
              parts.contains(where: { !$0.isEmpty }),
              parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }) else {
            throw LoadingError.invalidWeight
        }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= 3 else { throw LoadingError.tooManyDecimals }
        guard let whole = Int64(parts[0].isEmpty ? "0" : String(parts[0])),
              let fractional = Int64(fraction.padding(toLength: 3, withPad: "0", startingAt: 0)) else {
            throw LoadingError.weightOutOfRange
        }
        let (scaled, overflow) = whole.multipliedReportingOverflow(by: 1_000)
        let (value, sumOverflow) = scaled.addingReportingOverflow(fractional)
        guard !overflow, !sumOverflow else { throw LoadingError.weightOutOfRange }
        return try WeightAmount(milliUnits: value, unit: unit)
    }

    private enum CodingKeys: String, CodingKey { case milliUnits, unit }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(milliUnits: values.decode(Int64.self, forKey: .milliUnits),
                      unit: values.decode(WeightUnit.self, forKey: .unit))
    }
}
