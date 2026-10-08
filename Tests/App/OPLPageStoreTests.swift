import XCTest
import LiftingCore
@testable import PowerliftingApp

private enum ScreenReply: Sendable { case data(Data), error(OPLError) }
private actor ScreenTransport: OPLTransport {
    private var replies: [ScreenReply]
    private var requested: [URL] = []
    init(_ replies: [ScreenReply]) { self.replies = replies }
    func get(_ url: URL) throws -> Data {
        requested.append(url)
        guard !replies.isEmpty else { throw OPLError.invalidResponse }
        switch replies.removeFirst() { case .data(let data): return data; case .error(let error): throw error }
    }
    func count() -> Int { requested.count }
}
private actor ScreenCache: OPLCache {
    private var data: [String: Data] = [:]
    func read(_ key: String) -> Data? { data[key] }
    func write(_ bytes: Data, key: String) { data[key] = bytes }
}
private actor DeferredScreenTransport: OPLTransport {
    private let old: Data, new: Data
    private var count = 0
    private var continuation: CheckedContinuation<Data, Never>?
    private var ready: [CheckedContinuation<Void, Never>] = []
    init(old: Data, new: Data) { self.old = old; self.new = new }
    func get(_ url: URL) async -> Data {
        count += 1
        if count == 1 {
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                ready.forEach { $0.resume() }; ready = []
            }
        }
        return new
    }
    func waitForFirst() async {
        if continuation != nil { return }
        await withCheckedContinuation { ready.append($0) }
    }
    func releaseFirst() { continuation?.resume(returning: old); continuation = nil }
}

/// Simulator XCTest SOURCES only. Synthetic DTOs; no UI/Swift execution claimed.
final class OPLPageStoreTests: XCTestCase {
    private let a = String(repeating: "a", count: 64), b = String(repeating: "b", count: 64)
    private let query = OPLQuery(path: "lifters", parameters: ["q": "Synthetic"])
    private func bytes(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    private func metadata(_ version: String) throws -> Data {
        try bytes(["dataset": ["schemaVersion": 1, "version": version, "rows": 8, "lifters": 4], "status": [:],
            "sourceDate": "2025-01-01", "sourceStale": false, "checkStale": false, "attribution": "Synthetic app-state fixture"])
    }
    private func page(_ version: String, name: String, cursor: String? = nil) throws -> Data {
        try bytes(["version": version, "results": [["Name": name, "lifterId": "U3ludGhldGlj"]],
            "nextCursor": cursor.map { $0 as Any } ?? NSNull()])
    }
    private func repository(_ transport: any OPLTransport) throws -> OPLRepository {
        try OPLRepository(baseURL: XCTUnwrap(URL(string: "https://fixture.invalid")), transport: transport, cache: ScreenCache())
    }
    @MainActor func testRecoveryAdoptionResetKeepsNewRowsAndDoesNotGrantAnotherAutomaticRetry() async throws {
        let transport = ScreenTransport([.error(.versionUnavailable), .data(try metadata(b)),
            .data(try page(b, name: "Synthetic new", cursor: "new-next")), .error(.versionUnavailable)])
        let client = try repository(transport), store = OPLPageStore<OPLLifter>()
        var adoptions = 0
        let adopt: @MainActor (OPLDelivery<OPLDataset>, OPLRepository) -> Void = { _, _ in adoptions += 1 }
        await store.reset(client: client, version: a, query: query, adoptDataset: adopt)
        XCTAssertEqual(store.items.first?.name, "Synthetic new"); XCTAssertEqual(store.loadedVersion, b); XCTAssertEqual(adoptions, 1)
        // Simulate SwiftUI's task reset after shared metadata revision changes.
        await store.reset(client: client, version: b, query: query, adoptDataset: adopt)
        let afterReset = await transport.count(); XCTAssertEqual(afterReset, 3); XCTAssertEqual(store.items.count, 1)
        await store.more()
        let afterMore = await transport.count(); XCTAssertEqual(afterMore, 4)
        XCTAssertTrue(store.items.isEmpty); XCTAssertNil(store.cursor); XCTAssertNotNil(store.error); XCTAssertEqual(adoptions, 1)
    }
    @MainActor func testBusyAfterDatasetRecoveryKeepsNewVersionAndManualRetryRestartsFirstPage() async throws {
        let transport = ScreenTransport([.error(.versionUnavailable), .data(try metadata(b)),
            .error(.busy(retryAfterSeconds: 1)), .data(try page(b, name: "Synthetic recovered"))])
        let client = try repository(transport), store = OPLPageStore<OPLLifter>()
        var adopted: String?
        let adopt: @MainActor (OPLDelivery<OPLDataset>, OPLRepository) -> Void = { delivery, _ in adopted = delivery.value.dataset?.version }
        await store.reset(client: client, version: a, query: query, adoptDataset: adopt)
        XCTAssertEqual(adopted, b); XCTAssertEqual(store.loadedVersion, b)
        XCTAssertTrue(store.items.isEmpty); XCTAssertNil(store.cursor); XCTAssertTrue(store.error?.contains("busy") == true)
        await store.reset(client: client, version: b, query: query, adoptDataset: adopt)
        let beforeRetry = await transport.count(); XCTAssertEqual(beforeRetry, 3)
        await store.retry()
        let afterRetry = await transport.count(); XCTAssertEqual(afterRetry, 4)
        XCTAssertEqual(store.items.first?.name, "Synthetic recovered"); XCTAssertNil(store.error); XCTAssertFalse(store.loading)
    }
    @MainActor func testLatePreviousQueryCannotAppendToNewVersionOrOverwriteLoading() async throws {
        let transport = DeferredScreenTransport(old: try page(a, name: "Synthetic old"), new: try page(b, name: "Synthetic new"))
        let client = try repository(transport), store = OPLPageStore<OPLLifter>()
        let first = Task { await store.reset(client: client, version: a, query: query) }
        await transport.waitForFirst()
        await store.reset(client: client, version: b, query: OPLQuery(path: "lifters", parameters: ["q": "Different"]))
        await transport.releaseFirst(); await first.value
        XCTAssertEqual(store.items.map(\.name), ["Synthetic new"]); XCTAssertEqual(store.loadedVersion, b)
        XCTAssertFalse(store.loading); XCTAssertNil(store.error)
    }
    @MainActor func testCancelledSearchDebounceLeavesNoLoadingOrTransportRequest() async throws {
        let transport = ScreenTransport([]), store = OPLPageStore<OPLLifter>(), client = try repository(transport)
        let task = Task { await store.reset(client: client, version: a, query: query, delayNanoseconds: 1_000_000_000) }
        await Task.yield(); task.cancel(); await task.value
        let requests = await transport.count(); XCTAssertEqual(requests, 0)
        XCTAssertFalse(store.loading); XCTAssertNil(store.error)
    }
}
