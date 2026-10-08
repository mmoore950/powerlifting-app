import Foundation

public struct OPLDataset: Codable, Sendable {
    public struct Manifest: Codable, Sendable {
        public let schemaVersion: Int
        public let version: String
        public let rows: Int
        public let lifters: Int
    }
    public struct Status: Codable, Sendable {
        public let lastSuccessfulCheckAt: String?
        public let lastSuccessfulImportAt: String?
        public let lastError: String?
        public let nextCheckAt: String?
    }
    public struct Validation: Codable, Sendable {
        public let version: String
        public let validatedAt: String
    }
    public let dataset: Manifest?
    public let status: Status
    public let sourceDate: String?
    public let checkStale: Bool
    public let sourceStale: Bool
    public let attribution: String
    public let validation: Validation?
    public let statusMatchesDataset: Bool?

    public func validate() throws {
        guard let dataset else { throw OPLError.noDataset }
        guard dataset.schemaVersion == 1, Self.validVersion(dataset.version), dataset.rows > 0,
              dataset.lifters > 0 else { throw OPLError.invalidResponse }
        if let validation, validation.version != dataset.version { throw OPLError.wrongVersion }
    }
    public static func validVersion(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }
    public static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    public func checkIsStale(now: Date = Date()) -> Bool {
        guard let last = Self.date(status.lastSuccessfulCheckAt) else { return true }
        return checkStale || now.timeIntervalSince(last) > 86_400
    }
    public func sourceIsStale(now: Date = Date()) -> Bool {
        guard let sourceDate, let last = Self.date(sourceDate + "T00:00:00Z") else { return true }
        return sourceStale || now.timeIntervalSince(last) > 2 * 86_400
    }
}

public struct OPLLifter: Codable, Identifiable, Sendable {
    public let name: String
    public let lifterID: String
    public var id: String { lifterID }
    public init(name: String, lifterID: String) { self.name = name; self.lifterID = lifterID }
    enum CodingKeys: String, CodingKey { case name = "Name", lifterID = "lifterId" }
}

public struct OPLResult: Codable, Identifiable, Sendable {
    public let rowID: Int
    public let name: String
    public let lifterID: String
    public let sex: String
    public let equipment: String
    public let event: String
    public let date: String
    public let meet: String
    public let federation: String
    public let division: String
    public let place: String
    public let tested: String
    public let weightClass: String
    public let bodyweight: Double?
    public let total: Double?
    public let squat: Double?
    public let bench: Double?
    public let deadlift: Double?
    public let dots: Double?
    public var id: String { "\(lifterID):\(rowID)" }
    enum CodingKeys: String, CodingKey {
        case rowID = "row_id", name = "Name", lifterID = "lifterId", sex = "Sex"
        case equipment = "Equipment", event = "Event", date = "Date", meet = "MeetName"
        case federation = "Federation", division = "Division", place = "Place", tested = "Tested"
        case weightClass = "WeightClassKg", bodyweight = "BodyweightKg", total = "TotalKg"
        case squat = "Best3SquatKg", bench = "Best3BenchKg", deadlift = "Best3DeadliftKg", dots = "Dots"
    }
}

public struct OPLPage<Item: Codable & Sendable>: Codable, Sendable {
    public let version: String
    public let results: [Item]
    public let nextCursor: String?
    public let label: String?
}

public struct OPLDelivery<Value: Sendable>: Sendable {
    public let value: Value
    public let savedAt: Date
    public let offline: Bool
    public let notice: String?
}

public struct OPLQuery: Sendable, Equatable {
    public let path: String
    public let parameters: [String: String]
    public init(path: String, parameters: [String: String] = [:]) {
        self.path = path; self.parameters = parameters
    }
}

public struct OPLPageRecovery<Item: Codable & Sendable>: Sendable {
    public let page: OPLDelivery<OPLPage<Item>>
    public let restarted: Bool
}

public enum OPLError: Error, LocalizedError, Sendable, Equatable {
    case invalidEndpoint, noDataset, invalidResponse, wrongVersion, service(Int, String), noCachedData
    case versionUnavailable, busy(retryAfterSeconds: Int?), queryTimedOut
    public static func fromService(status: Int, code: String, retryAfter: String? = nil) -> OPLError {
        if status == 409 && code == "VERSION_UNAVAILABLE" { return .versionUnavailable }
        if status == 504 && code == "QUERY_TIMEOUT" { return .queryTimedOut }
        if status == 503 && ["QUERY_BUSY", "QUERY_QUEUE_TIMEOUT", "SNAPSHOT_BUSY"].contains(code.components(separatedBy: ":").first ?? code) {
            let seconds = retryAfter.flatMap { Int($0) }.flatMap { (0...3_600).contains($0) ? $0 : nil }
            return .busy(retryAfterSeconds: seconds)
        }
        if status == 503 && code == "NO_DATASET" { return .noDataset }
        return .service(status, String(code.prefix(300)))
    }
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Enter an HTTPS service URL without credentials, query or fragment."
        case .noDataset: return "The service has no published dataset yet."
        case .invalidResponse: return "The service returned an unsupported or invalid response."
        case .wrongVersion: return "The result belongs to a different dataset. Refresh before continuing."
        case .service(let status, let message): return "Service error \(status): \(message)"
        case .noCachedData: return "This page has not been saved for offline use."
        case .versionUnavailable: return "This saved query version has expired. Refresh to restart the results."
        case .busy(let seconds):
            if let seconds, seconds > 0 { return "The data service is busy. Try again in about \(seconds) \(seconds == 1 ? "second" : "seconds")." }
            return "The data service is busy. Try again shortly."
        case .queryTimedOut: return "This query took too long. Narrow the filters or try again."
        }
    }
}
