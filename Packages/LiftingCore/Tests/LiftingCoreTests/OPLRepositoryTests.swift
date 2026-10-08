import XCTest
@testable import LiftingCore

private enum TransportReply: Sendable { case data(Data), fail }
private enum FixtureFailure: Error { case unavailable, disk }
private actor FixtureTransport: OPLTransport {
    private var replies: [TransportReply]
    private var requested: [URL] = []
    init(_ replies: [TransportReply]) { self.replies = replies }
    func get(_ url: URL) throws -> Data {
        requested.append(url)
        guard !replies.isEmpty else { throw FixtureFailure.unavailable }
        switch replies.removeFirst() {
        case .data(let data): return data
        case .fail: throw FixtureFailure.unavailable
        }
    }
    func urls() -> [URL] { requested }
}
private actor FixtureCache: OPLCache {
    private var contents: [String: Data] = [:]
    private var failWrites = false
    func read(_ key: String) -> Data? { contents[key] }
    func write(_ data: Data, key: String) throws {
        if failWrites { throw FixtureFailure.disk }
        contents[key] = data
    }
    func failStorage() { failWrites = true }
    func count() -> Int { contents.count }
    func corrupt() { for key in contents.keys { contents[key] = Data("invalid".utf8) } }
}

/// Synthetic service responses; no claim that these are real lifters or dated rankings.
final class OPLRepositoryTests: XCTestCase {
    private let a = String(repeating: "a", count: 64)
    private let b = String(repeating: "b", count: 64)
    private func json(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    private func metadata(_ version: String, source: String = "2025-01-01") throws -> Data {
        try json(["dataset": ["version": version, "schemaVersion": 1, "rows": 8, "lifters": 4],
            "status": ["lastSuccessfulCheckAt": "2025-01-04T00:00:00.123Z"],
            "sourceDate": source, "sourceStale": false, "checkStale": false,
            "validation": ["version": version, "validatedAt": "2025-01-03T00:00:00Z"],
            "statusMatchesDataset": true, "attribution": "Synthetic fixture"])
    }
    private func page(_ version: String, cursor: String? = nil) throws -> Data {
        let next: Any = cursor.map { $0 as Any } ?? NSNull()
        return try json(["version": version, "results": [["Name": "Synthetic Alice #1", "lifterId": "U3ludGhldGljIEFsaWNlICMx"]],
            "nextCursor": next])
    }
    private func client(_ transport: FixtureTransport, _ cache: any OPLCache,
        endpoint: String = "https://fixture.invalid/api") throws -> OPLRepository {
        try OPLRepository(baseURL: XCTUnwrap(URL(string: endpoint)), transport: transport, cache: cache)
    }

    func testVersionScopedOfflinePagesAndSourceDateTransitions() async throws {
        let transport = FixtureTransport([.data(try metadata(a)), .data(try page(a, cursor: "cursor-one")),
            .data(try metadata(b, source: "2025-02-01")), .fail, .fail])
        let cache = FixtureCache(), repository = try client(transport, cache)
        let first = try await repository.dataset()
        XCTAssertEqual(first.value.sourceDate, "2025-01-01")
        let query = OPLQuery(path: "lifters", parameters: ["q": "Synthetic Alice"])
        let saved = try await repository.page(query, version: a, as: OPLLifter.self)
        XCTAssertEqual(saved.value.nextCursor, "cursor-one")
        let changed = try await repository.dataset()
        XCTAssertEqual(changed.value.dataset?.version, b)
        XCTAssertEqual(changed.value.sourceDate, "2025-02-01")
        do {
            _ = try await repository.page(query, version: b, as: OPLLifter.self)
            XCTFail("A cached page must not substitute for B")
        } catch { XCTAssertFalse(error is CancellationError) }
        let old = try await repository.page(query, version: a, as: OPLLifter.self)
        XCTAssertTrue(old.offline); XCTAssertEqual(old.value.version, a)
        XCTAssertEqual(old.savedAt, saved.savedAt)
        let urls = await transport.urls()
        XCTAssertTrue(urls[3].query?.contains("version=" + b) == true)
    }

    func testWrongVersionIsNotStoredAndCursorIsKeptWithVersion() async throws {
        let transport = FixtureTransport([.data(try page(b)), .data(try page(a)), .data(try page(a))])
        let cache = FixtureCache(), repository = try client(transport, cache)
        let query = OPLQuery(path: "lifters", parameters: ["q": "Synthetic + name"])
        do {
            _ = try await repository.page(query, version: a, as: OPLLifter.self)
            XCTFail("Mismatched version accepted")
        } catch OPLError.wrongVersion {} catch { XCTFail("Unexpected error: \(error)") }
        let count = await cache.count(); XCTAssertEqual(count, 0)
        _ = try await repository.page(query, version: a, as: OPLLifter.self)
        _ = try await repository.page(query, version: a, cursor: "opaque+/=", as: OPLLifter.self)
        let urls = await transport.urls()
        let url = try XCTUnwrap(urls.last)
        let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(parameters.first { $0.name == "cursor" }?.value, "opaque+/=")
        XCTAssertEqual(parameters.first { $0.name == "version" }?.value, a)
        XCTAssertEqual(parameters.first { $0.name == "q" }?.value, "Synthetic + name")
        XCTAssertTrue(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery?.contains("%2B") == true)
    }

    func testMetadataFallbackDoesNotChangeSourceOrCheckDates() async throws {
        let transport = FixtureTransport([.data(try metadata(a)), .fail, .fail])
        let cache = FixtureCache(), repository = try client(transport, cache)
        _ = try await repository.dataset()
        let fallback = try await repository.dataset()
        XCTAssertTrue(fallback.offline)
        XCTAssertEqual(fallback.value.sourceDate, "2025-01-01")
        XCTAssertTrue(fallback.value.checkIsStale(now: try XCTUnwrap(OPLDataset.date("2025-01-06T00:00:00Z"))))
        XCTAssertTrue(fallback.value.sourceIsStale(now: try XCTUnwrap(OPLDataset.date("2025-01-06T00:00:00Z"))))
        await cache.corrupt()
        do { _ = try await repository.dataset(); XCTFail("Corrupt cache accepted") } catch {}
    }

    func testEndpointsAreIsolatedAndFailedStorageIsVisible() async throws {
        let cache = FixtureCache()
        let first = try client(FixtureTransport([.data(try metadata(a))]), cache)
        _ = try await first.dataset()
        let other = try client(FixtureTransport([.fail]), cache, endpoint: "https://other.invalid")
        do { _ = try await other.dataset(); XCTFail("Other service cache leaked") } catch {}
        await cache.failStorage()
        let noDisk = try client(FixtureTransport([.data(try metadata(a))]), cache)
        let online = try await noDisk.dataset()
        XCTAssertFalse(online.offline); XCTAssertNotNil(online.notice)
        XCTAssertThrowsError(try client(FixtureTransport([]), cache, endpoint: "http://127.0.0.1:8787"))
        XCTAssertThrowsError(try client(FixtureTransport([]), cache, endpoint: "https://user:pass@fixture.invalid"))
    }

    func testRealDiskPersistenceAndBoundedEviction() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = OPLDiskCache(directory: root, byteLimit: 1_600)
        let payload = Data(repeating: 42, count: 600)
        try await cache.write(payload, key: "service-a:version-a")
        let reopened = OPLDiskCache(directory: root, byteLimit: 1_600)
        let data = try await reopened.read("service-a:version-a")
        XCTAssertEqual(data, payload)
        let absent = try await reopened.read("service-b:version-a"); XCTAssertNil(absent)
        try await cache.write(payload, key: "service-a:version-b")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])
        let bytes = try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThanOrEqual(bytes, 1_600)
    }

    func testHistoryPreservesMissingAndFailedValuesAndExactSuffixes() throws {
        let bytes = try json(["row_id": 7, "Name": "Synthetic Alice #1", "lifterId": "U3ludGhldGljIEFsaWNlICMx",
            "Sex": "F", "Equipment": "Raw", "Event": "SBD", "Date": "2025-01-01", "MeetName": "Synthetic meet",
            "Federation": "FIX", "Division": "Open", "Place": "DQ", "Tested": "", "WeightClassKg": "+",
            "BodyweightKg": 70.5, "TotalKg": NSNull(), "Best3SquatKg": -100, "Best3BenchKg": NSNull(), "Best3DeadliftKg": 150,
            "Dots": NSNull()])
        let result = try JSONDecoder().decode(OPLResult.self, from: bytes)
        XCTAssertEqual(result.name, "Synthetic Alice #1"); XCTAssertNil(result.total)
        XCTAssertEqual(result.squat, -100); XCTAssertNil(result.bench)
        XCTAssertEqual(result.weightClass, "+"); XCTAssertEqual(result.place, "DQ")
    }

    func testFrozenGenuineServiceContractExcerpt() throws {
        struct Evidence: Decodable {
            let dataset: OPLDataset
            let search: OPLPage<OPLLifter>
            let history: OPLPage<OPLResult>
            let rankings: OPLPage<OPLResult>
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "opl-genuine-excerpt", withExtension: "json", subdirectory: "Fixtures"))
        let proof = try JSONDecoder().decode(Evidence.self, from: Data(contentsOf: url))
        try proof.dataset.validate()
        XCTAssertEqual(proof.dataset.sourceDate, "2026-10-03")
        XCTAssertEqual(proof.search.results.first?.name, "Taylor Atwood")
        XCTAssertEqual(proof.history.results.first?.total, 866.5)
        XCTAssertEqual(proof.rankings.results.first?.name, "Brittany Schlater")
        XCTAssertEqual(proof.search.version, proof.history.version)
        XCTAssertEqual(proof.rankings.version, proof.dataset.dataset?.version)
    }
}
