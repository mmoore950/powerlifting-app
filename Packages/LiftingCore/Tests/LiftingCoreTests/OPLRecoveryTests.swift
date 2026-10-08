import XCTest
@testable import LiftingCore

private enum RecoveryReply: Sendable { case data(Data), typed(OPLError), offline }
private enum RecoveryFixtureError: Error { case offline }
private actor RecoveryTransport: OPLTransport {
    private var replies: [RecoveryReply]
    private var requested: [URL] = []
    init(_ replies: [RecoveryReply]) { self.replies = replies }
    func get(_ url: URL) throws -> Data {
        requested.append(url)
        guard !replies.isEmpty else { throw RecoveryFixtureError.offline }
        switch replies.removeFirst() {
        case .data(let data): return data
        case .typed(let error): throw error
        case .offline: throw RecoveryFixtureError.offline
        }
    }
    func urls() -> [URL] { requested }
}
private actor RecoveryCache: OPLCache {
    private var contents: [String: Data] = [:]
    func read(_ key: String) -> Data? { contents[key] }
    func write(_ data: Data, key: String) { contents[key] = data }
}
private actor RecoveryEvents {
    private var values: [String] = []
    func add(_ value: String) { values.append(value) }
    func all() -> [String] { values }
}

/// Native test SOURCES only. All responses and lifters below are synthetic.
final class OPLRecoveryTests: XCTestCase {
    private let a = String(repeating: "a", count: 64), b = String(repeating: "b", count: 64)
    private let query = OPLQuery(path: "lifters", parameters: ["q": "Synthetic"])
    private func bytes(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    private func metadata(_ version: String) throws -> Data {
        try bytes(["dataset": ["schemaVersion": 1, "version": version, "rows": 8, "lifters": 4],
            "status": ["lastSuccessfulCheckAt": "2025-01-01T00:00:00Z"], "sourceDate": "2025-01-01",
            "sourceStale": false, "checkStale": false, "attribution": "Synthetic recovery fixture"])
    }
    private func page(_ version: String, name: String = "Synthetic Alice", cursor: String? = nil) throws -> Data {
        try bytes(["version": version, "results": [["Name": name, "lifterId": "U3ludGhldGlj"]],
            "nextCursor": cursor.map { $0 as Any } ?? NSNull()])
    }
    private func repository(_ transport: RecoveryTransport) throws -> OPLRepository {
        try OPLRepository(baseURL: XCTUnwrap(URL(string: "https://fixture.invalid")), transport: transport, cache: RecoveryCache())
    }
    func testExpiredCachedCursorRefreshesOnlineAndRestartsWithoutOldCursor() async throws {
        let transport = RecoveryTransport([.data(try page(a, name: "Synthetic old", cursor: "old-next")),
            .typed(.versionUnavailable), .data(try metadata(b)), .data(try page(b, name: "Synthetic new", cursor: "new-next"))])
        let client = try repository(transport), events = RecoveryEvents()
        _ = try await client.page(query, version: a, cursor: "expired+/=", as: OPLLifter.self)
        let result = try await client.recoveringPage(query, version: a, cursor: "expired+/=", as: OPLLifter.self,
            onExpiration: { await events.add("expired") }, onDataset: { delivery in await events.add(delivery.value.dataset?.version ?? "missing") })
        XCTAssertTrue(result.restarted); XCTAssertFalse(result.page.offline)
        XCTAssertEqual(result.page.value.version, b); XCTAssertEqual(result.page.value.results.first?.name, "Synthetic new")
        XCTAssertEqual(result.page.value.nextCursor, "new-next")
        let recorded = await events.all(); XCTAssertEqual(recorded, ["expired", b])
        let urls = await transport.urls(); XCTAssertEqual(urls.count, 4); XCTAssertEqual(urls[2].path, "/dataset")
        let restarted = URLComponents(url: urls[3], resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertNil(restarted.first { $0.name == "cursor" }); XCTAssertEqual(restarted.first { $0.name == "version" }?.value, b)
    }
    func testDefinitiveRetirementDoesNotSubstituteSavedOldPage() async throws {
        let transport = RecoveryTransport([.data(try page(a)), .typed(.versionUnavailable)])
        let client = try repository(transport)
        _ = try await client.page(query, version: a, as: OPLLifter.self)
        do { _ = try await client.page(query, version: a, as: OPLLifter.self); XCTFail("Retired cache hid HTTP409") }
        catch OPLError.versionUnavailable {} catch { XCTFail("Unexpected error: \(error)") }
        let urls = await transport.urls(); XCTAssertEqual(urls.count, 2)
    }
    func testSecondExpirationStopsAndCallerBudgetCanDisableAutomaticRecovery() async throws {
        let transport = RecoveryTransport([.typed(.versionUnavailable), .data(try metadata(b)), .typed(.versionUnavailable)])
        let client = try repository(transport)
        do { _ = try await client.recoveringPage(query, version: a, as: OPLLifter.self); XCTFail("Repeated expiration accepted") }
        catch OPLError.versionUnavailable {} catch { XCTFail("Unexpected error: \(error)") }
        let urls = await transport.urls(); XCTAssertEqual(urls.count, 3)
        let limited = RecoveryTransport([.typed(.versionUnavailable)]), events = RecoveryEvents()
        let limitedClient = try repository(limited)
        do {
            _ = try await limitedClient.recoveringPage(query, version: a, as: OPLLifter.self, allowRecovery: false,
                onExpiration: { await events.add("cleared") })
            XCTFail("Exhausted budget retried")
        } catch OPLError.versionUnavailable {} catch { XCTFail("Unexpected error: \(error)") }
        let limitedURLs = await limited.urls(), recorded = await events.all()
        XCTAssertEqual(limitedURLs.count, 1); XCTAssertEqual(recorded, ["cleared"])
    }
    func testRecoveryMetadataCannotFallBackToSavedExpiredVersion() async throws {
        let transport = RecoveryTransport([.data(try metadata(a)), .typed(.versionUnavailable), .offline])
        let client = try repository(transport)
        _ = try await client.dataset()
        do { _ = try await client.recoveringPage(query, version: a, as: OPLLifter.self); XCTFail("Offline metadata reused expired version") }
        catch RecoveryFixtureError.offline {} catch { XCTFail("Unexpected error: \(error)") }
        let urls = await transport.urls(); XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(urls.map(\.path), ["/dataset", "/lifters", "/dataset"])
    }
    func testBusyAndTimeoutUseSameVersionSavedPageAndClearTypedMessagesWithoutRetries() async throws {
        let transport = RecoveryTransport([.data(try page(a)), .typed(.busy(retryAfterSeconds: 1)), .typed(.queryTimedOut)])
        let client = try repository(transport)
        _ = try await client.page(query, version: a, as: OPLLifter.self)
        let busy = try await client.recoveringPage(query, version: a, as: OPLLifter.self)
        XCTAssertFalse(busy.restarted); XCTAssertTrue(busy.page.offline)
        XCTAssertTrue(busy.page.notice?.contains("busy") == true); XCTAssertEqual(busy.page.value.version, a)
        let timeout = try await client.recoveringPage(query, version: a, as: OPLLifter.self)
        XCTAssertTrue(timeout.page.offline); XCTAssertTrue(timeout.page.notice?.contains("too long") == true)
        let urls = await transport.urls(); XCTAssertEqual(urls.count, 3)
        let empty = try repository(RecoveryTransport([.typed(.busy(retryAfterSeconds: nil))]))
        do { _ = try await empty.page(query, version: a, as: OPLLifter.self); XCTFail("No-cache busy error lost") }
        catch OPLError.busy(_) {} catch { XCTFail("Unexpected error: \(error)") }
    }
    func testHTTPClassificationLimitsRecoveryToDefinitiveCodeAndBoundsRetryHint() {
        XCTAssertEqual(OPLError.fromService(status: 409, code: "VERSION_UNAVAILABLE"), .versionUnavailable)
        XCTAssertEqual(OPLError.fromService(status: 409, code: "CURSOR_VERSION_MISMATCH"), .service(409, "CURSOR_VERSION_MISMATCH"))
        XCTAssertEqual(OPLError.fromService(status: 503, code: "QUERY_BUSY", retryAfter: "1"), .busy(retryAfterSeconds: 1))
        XCTAssertEqual(OPLError.fromService(status: 503, code: "SNAPSHOT_BUSY: pending owner", retryAfter: "99999"), .busy(retryAfterSeconds: nil))
        XCTAssertEqual(OPLError.fromService(status: 504, code: "QUERY_TIMEOUT"), .queryTimedOut)
        XCTAssertEqual(OPLError.fromService(status: 503, code: "NO_DATASET"), .noDataset)
    }
}
