import XCTest
@testable import LiftingCore

private enum ProfileReply: Sendable { case data(Data), error(OPLError) }
private actor ProfileTransport: OPLTransport {
    var replies: [ProfileReply]
    var requests: [URL] = []
    init(_ replies: [ProfileReply]) { self.replies = replies }
    func get(_ url: URL) throws -> Data {
        requests.append(url)
        guard !replies.isEmpty else { throw OPLError.noCachedData }
        switch replies.removeFirst() { case .data(let data): return data; case .error(let error): throw error }
    }
    func urls() -> [URL] { requests }
}
private actor ProfileCache: OPLCache {
    var values: [String: Data] = [:]
    func read(_ key: String) -> Data? { values[key] }
    func write(_ data: Data, key: String) { values[key] = data }
}

/// Synthetic contract test source. Apple execution is required separately.
final class OPLProfileTests: XCTestCase {
    private let version = String(repeating: "a", count: 64)
    private let next = String(repeating: "b", count: 64)
    private let scope = ["sex": "F", "equipment": "Raw", "event": "SBD", "weightClass": "75+"]
    private let sourceName = "Synthetic Profile #1"
    private var id: String { Data(sourceName.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    private var query: OPLQuery { OPLQuery(path: "lifters/\(id)/summary", parameters: scope) }
    private func bytes(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    private func result() -> [String: Any] {
        ["row_id": 1, "Name": sourceName, "lifterId": id, "Sex": "F", "Equipment": "Raw", "Event": "SBD",
         "Date": "2025-01-01", "MeetName": "Synthetic meet", "Federation": "FIX", "Division": "Open",
         "Place": "1", "Tested": "Yes", "WeightClassKg": "75+", "BodyweightKg": 70, "TotalKg": 500]
    }
    private func object() -> [String: Any] { ["Name": sourceName, "lifterId": id, "scope": scope, "bests": [["metric": "total", "result": result()]]] }
    private func page(_ version: String, object: [String: Any]? = nil) throws -> Data {
        try bytes(["version": version, "results": [object ?? self.object()], "nextCursor": NSNull()])
    }
    private func client(_ transport: ProfileTransport) throws -> OPLRepository {
        try OPLRepository(baseURL: XCTUnwrap(URL(string: "https://fixture.invalid")), transport: transport, cache: ProfileCache())
    }
    func testAdditionalDraftApplyAndClearPreserveContextAndLiteralSourceValues() {
        let applied = scope.merging(["metric": "bench", "tested": "yes", "federation": "OLD", "from": "2020-01-01"]) { _, new in new }
        var draft = OPLProfileScope.additionalDraft(from: applied)
        XCTAssertEqual(draft["federation"], "OLD"); XCTAssertNil(draft["sex"])
        draft["federation"] = "  FIX  "; draft["from"] = " "; draft["to"] = "2025-01-01"
        draft["bodyweightMin"] = " 60.50 "; draft["ignored"] = "unsupported"
        XCTAssertEqual(applied["federation"], "OLD"); XCTAssertEqual(applied["from"], "2020-01-01")
        let next = OPLProfileScope.applyingAdditional(draft, to: applied)
        XCTAssertEqual(next["federation"], "FIX"); XCTAssertNil(next["from"]); XCTAssertEqual(next["to"], "2025-01-01")
        XCTAssertEqual(next["bodyweightMin"], "60.50"); XCTAssertNil(next["ignored"])
        for key in ["sex", "equipment", "event", "tested", "metric"] { XCTAssertEqual(next[key], applied[key]) }
        for label in ["+", "120+", "-74"] {
            XCTAssertEqual(OPLProfileScope.applyingAdditional(["weightClass": label], to: next)["weightClass"], label)
        }
        let cleared = OPLProfileScope.applyingAdditional([:], to: next)
        XCTAssertTrue(OPLProfileScope.additionalDraft(from: cleared).isEmpty)
        for key in ["sex", "equipment", "event", "tested", "metric"] { XCTAssertEqual(cleared[key], applied[key]) }
        // No approximate client validation: rejected service text is transmitted verbatim on Apply.
        XCTAssertEqual(OPLProfileScope.applyingAdditional(["from": "invalid date"], to: next)["from"], "invalid date")
    }
    func testBoundedDTOAndRankingContextPreserveIdentityAndIndependentMetricSemantics() throws {
        let value = try JSONDecoder().decode(OPLProfileSummary.self, from: bytes(object()))
        XCTAssertEqual(value.bests.first?.value, 500); XCTAssertEqual(value.scope, scope)
        let filters = scope.merging(["metric": "bench", "federation": "FIX", "from": "2020-01-01", "bodyweightMin": "60", "tested": "yes"]) { _, new in new }
        let inherited = OPLProfileScope.parameters(from: filters)
        XCTAssertNil(inherited["metric"]); XCTAssertEqual(inherited["sex"], "F"); XCTAssertEqual(inherited["weightClass"], "75+")
        XCTAssertEqual(inherited["federation"], "FIX"); XCTAssertEqual(inherited["from"], "2020-01-01")
        XCTAssertEqual(inherited["bodyweightMin"], "60"); XCTAssertEqual(inherited["tested"], "yes")
        var bad = object(); bad["lifterId"] = "wrong"
        XCTAssertThrowsError(try JSONDecoder().decode(OPLProfileSummary.self, from: bytes(bad)))
        bad = object(); bad["bests"] = [["metric": "total", "result": result()], ["metric": "total", "result": result()]]
        XCTAssertThrowsError(try JSONDecoder().decode(OPLProfileSummary.self, from: bytes(bad)))
        for metric in ["unknown", "bench"] {
            bad = object(); bad["bests"] = [["metric": metric, "result": result()]]
            XCTAssertThrowsError(try JSONDecoder().decode(OPLProfileSummary.self, from: bytes(bad)))
        }
        var wrongRow = result(); wrongRow["Equipment"] = "Wraps"
        bad = object(); bad["bests"] = [["metric": "total", "result": wrongRow]]
        XCTAssertThrowsError(try JSONDecoder().decode(OPLProfileSummary.self, from: bytes(bad)))
        bad = object(); bad["bests"] = []
        XCTAssertTrue(try JSONDecoder().decode(OPLProfileSummary.self, from: bytes(bad)).bests.isEmpty)
    }
    func testSummaryCacheIsOfflineReusableAndRejectsDifferentScope() async throws {
        let transport = ProfileTransport([.data(try page(version)), .error(.noCachedData)])
        let repository = try client(transport)
        let online = try await repository.page(query, version: version, as: OPLProfileSummary.self)
        let offline = try await repository.page(query, version: version, as: OPLProfileSummary.self)
        XCTAssertFalse(online.offline); XCTAssertTrue(offline.offline); XCTAssertEqual(offline.value.results.first?.scope, scope)
        var wrong = object(); wrong["scope"] = ["sex": "F", "equipment": "Raw", "event": "SBD"]
        let invalid = try client(ProfileTransport([.data(try page(version, object: wrong))]))
        do { _ = try await invalid.page(query, version: version, as: OPLProfileSummary.self); XCTFail("Different query scope accepted") }
        catch OPLError.invalidResponse {} catch { XCTFail("Unexpected: \(error)") }
        let urls = await transport.urls()
        XCTAssertEqual(urls.first?.path, "/lifters/\(id)/summary")
        XCTAssertTrue(urls.first?.absoluteString.contains("75%2B") == true)
    }
    func testSummaryExpirationRestartsOnNewVersionWithAllFiltersRetained() async throws {
        let metadata = try bytes(["dataset": ["schemaVersion": 1, "version": next, "rows": 8, "lifters": 4],
            "status": [:], "sourceDate": "2025-01-01", "sourceStale": false, "checkStale": false, "attribution": "Synthetic"])
        let transport = ProfileTransport([.error(.versionUnavailable), .data(metadata), .data(try page(next))])
        let repository = try client(transport)
        let recovery = try await repository.recoveringPage(query, version: version, as: OPLProfileSummary.self)
        XCTAssertTrue(recovery.restarted); XCTAssertEqual(recovery.page.value.version, next)
        XCTAssertEqual(recovery.page.value.results.first?.scope, scope)
        let urls = await transport.urls(); XCTAssertEqual(urls.count, 3)
        let items = URLComponents(url: try XCTUnwrap(urls.last), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "version" }?.value, next)
        for (key, value) in scope { XCTAssertEqual(items.first { $0.name == key }?.value, value) }
        XCTAssertNil(items.first { $0.name == "cursor" })
    }
}
