import Foundation
import CryptoKit

public protocol OPLTransport: Sendable {
    func get(_ url: URL) async throws -> Data
}

public struct OPLURLSessionTransport: OPLTransport {
    public init() {}
    public func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 4 * 1_024 * 1_024 else {
            throw OPLError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServiceError.self, from: data).error) ?? "Request failed"
            throw OPLError.fromService(status: http.statusCode, code: message, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        }
        guard http.mimeType == "application/json" else { throw OPLError.invalidResponse }
        return data
    }
    private struct ServiceError: Decodable { let error: String }
}

public protocol OPLCache: Sendable {
    func read(_ key: String) async throws -> Data?
    func write(_ data: Data, key: String) async throws
}

/// Disk cache is bounded, atomic, and isolated by complete service/query/version key.
public actor OPLDiskCache: OPLCache {
    private struct Entry: Codable { let key: String; let bytes: Data }
    private let directory: URL
    private let byteLimit: Int
    public init(directory: URL, byteLimit: Int = 25 * 1_024 * 1_024) {
        self.directory = directory; self.byteLimit = max(1_024, byteLimit)
    }
    private func location(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }
    public func read(_ key: String) throws -> Data? {
        let file = location(key)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 6 * 1_024 * 1_024 else { throw OPLError.invalidResponse }
        let entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: file))
        guard entry.key == key else { throw OPLError.invalidResponse }
        return entry.bytes
    }
    public func write(_ data: Data, key: String) throws {
        guard data.count <= 4 * 1_024 * 1_024 else { throw OPLError.invalidResponse }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoded = try JSONEncoder().encode(Entry(key: key, bytes: data))
        guard encoded.count <= byteLimit else { throw OPLError.invalidResponse }
        try encoded.write(to: location(key), options: .atomic)
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            .filter { $0.pathExtension == "json" }
        var entries = try files.map { file -> (URL, Int, Date) in
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var bytes = entries.reduce(0) { $0 + $1.1 }
        while bytes > byteLimit || entries.count > 200 {
            let victim = entries.removeFirst()
            try FileManager.default.removeItem(at: victim.0)
            bytes -= victim.1
        }
    }
}

public actor OPLRepository {
    private struct Saved<Value: Codable>: Codable {
        let value: Value
        let savedAt: Date
    }
    private let baseURL: URL
    private let transport: any OPLTransport
    private let cache: any OPLCache
    public init(baseURL: URL, transport: any OPLTransport = OPLURLSessionTransport(), cache: any OPLCache) throws {
        guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host != nil, components.user == nil,
              components.password == nil, components.query == nil, components.fragment == nil else {
            throw OPLError.invalidEndpoint
        }
        self.baseURL = baseURL; self.transport = transport; self.cache = cache
    }
    public func dataset(requireOnline: Bool = false) async throws -> OPLDelivery<OPLDataset> {
        let url = try endpoint("dataset", parameters: [:])
        return try await fetch(url, as: OPLDataset.self, allowFallback: !requireOnline) { try $0.validate() }
    }
    public func page<Item: Codable & Sendable>(_ query: OPLQuery, version: String,
        cursor: String? = nil, as: Item.Type) async throws -> OPLDelivery<OPLPage<Item>> {
        guard OPLDataset.validVersion(version) else { throw OPLError.wrongVersion }
        var parameters = query.parameters
        parameters["limit"] = "25"; parameters["version"] = version
        if let cursor { parameters["cursor"] = cursor }
        let url = try endpoint(query.path, parameters: parameters)
        return try await fetch(url, as: OPLPage<Item>.self) { page in
            guard page.version == version else { throw OPLError.wrongVersion }
            guard page.results.count <= 25, (page.nextCursor?.count ?? 0) <= 2_048 else {
                throw OPLError.invalidResponse
            }
            if Item.self == OPLProfileSummary.self {
                let parts = query.path.split(separator: "/")
                guard parts.count == 3, parts[2] == "summary", page.results.count <= 1,
                      page.nextCursor == nil, page.results.allSatisfy({ item in
                          guard let summary = item as? OPLProfileSummary else { return false }
                          return summary.lifterID == String(parts[1]) && summary.scope == query.parameters
                      }) else { throw OPLError.invalidResponse }
            }
        }
    }
    /// One expiration recovery per caller-approved transaction. Never reuses the expired cursor.
    public func recoveringPage<Item: Codable & Sendable>(_ query: OPLQuery, version: String,
        cursor: String? = nil, as: Item.Type, allowRecovery: Bool = true,
        onExpiration: @Sendable () async -> Void = {},
        onDataset: @Sendable (OPLDelivery<OPLDataset>) async -> Void = { _ in }) async throws -> OPLPageRecovery<Item> {
        do {
            let result = try await page(query, version: version, cursor: cursor, as: Item.self)
            return OPLPageRecovery(page: result, restarted: false)
        } catch OPLError.versionUnavailable {
            try Task.checkCancellation()
            await onExpiration()
            try Task.checkCancellation()
            guard allowRecovery else { throw OPLError.versionUnavailable }
            // A saved metadata fallback could direct the retry back to the retired version.
            let latest = try await dataset(requireOnline: true)
            guard let freshVersion = latest.value.dataset?.version else { throw OPLError.noDataset }
            await onDataset(latest)
            try Task.checkCancellation()
            let restarted = try await page(query, version: freshVersion, cursor: nil, as: Item.self)
            return OPLPageRecovery(page: restarted, restarted: true)
        }
    }
    private func endpoint(_ path: String, parameters: [String: String]) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        let history = parts.count == 3 && parts[0] == "lifters" && ["results", "summary"].contains(parts[2])
            && !parts[1].isEmpty && parts[1].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
        guard ["dataset", "lifters", "rankings"].contains(path) || history else {
            throw OPLError.invalidEndpoint
        }
        let url = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw OPLError.invalidEndpoint
        }
        if !parameters.isEmpty {
            components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            // Node URLSearchParams uses form decoding: a literal plus must survive as %2B.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let result = components.url else { throw OPLError.invalidEndpoint }
        return result
    }
    private func fetch<Value: Codable & Sendable>(_ url: URL, as: Value.Type,
        allowFallback: Bool = true,
        validate: (Value) throws -> Void) async throws -> OPLDelivery<Value> {
        let key = url.absoluteString
        do {
            let data = try await transport.get(url)
            try Task.checkCancellation()
            guard data.count <= 4 * 1_024 * 1_024 else { throw OPLError.invalidResponse }
            let value = try JSONDecoder().decode(Value.self, from: data)
            try validate(value)
            let saved = Saved(value: value, savedAt: Date())
            let encoded = try JSONEncoder().encode(saved)
            var notice: String?
            do { try await cache.write(encoded, key: key) }
            catch { notice = "Loaded online; offline storage failed: \(error.localizedDescription)" }
            try Task.checkCancellation()
            return OPLDelivery(value: value, savedAt: saved.savedAt, offline: false, notice: notice)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            // Definitive retirement must reach the caller even if this old page was saved locally.
            if let issue = error as? OPLError, issue == .versionUnavailable { throw issue }
            guard allowFallback else { throw error }
            let networkError = error
            guard let data = try? await cache.read(key),
                  let saved = try? JSONDecoder().decode(Saved<Value>.self, from: data),
                  (try? validate(saved.value)) != nil else { throw networkError }
            try Task.checkCancellation()
            return OPLDelivery(value: saved.value, savedAt: saved.savedAt, offline: true,
                notice: "Showing saved data: \(networkError.localizedDescription)")
        }
    }
}
