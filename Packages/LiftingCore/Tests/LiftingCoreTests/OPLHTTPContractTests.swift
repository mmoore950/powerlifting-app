#if os(macOS)
import XCTest
import Foundation
@testable import LiftingCore

/// Only used by the isolated CI launcher. No production endpoint/ATS override.
private struct LoopbackContractTransport: OPLTransport {
    let port: Int
    func get(_ url: URL) async throws -> Data {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == "contract.fixture.invalid", parts.port == nil,
              parts.user == nil, parts.password == nil, parts.fragment == nil else {
            throw OPLError.invalidEndpoint
        }
        parts.scheme = "http"; parts.host = "127.0.0.1"; parts.port = port
        guard let local = parts.url else { throw OPLError.invalidEndpoint }
        return try await OPLURLSessionTransport().get(local)
    }
}

/// Real URLSession -> existing Node HTTP server/SQLite; all lifters are synthetic.
final class OPLHTTPContractTests: XCTestCase {
    private struct Ready: Decodable {
        let url: String
        let version: String
        let token: String
        let proof: String
    }
    func testActualNodeHTTPContract() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPL_HTTP_CONTRACT"] == "1" else {
            throw XCTSkip("Opt-in macOS HTTP fixture is not running; this is not an additional passed method")
        }
        let descriptor = URL(fileURLWithPath: try XCTUnwrap(environment["OPL_HTTP_DESCRIPTOR"]))
        let ready = try JSONDecoder().decode(Ready.self, from: Data(contentsOf: descriptor))
        let local = try XCTUnwrap(URLComponents(string: ready.url))
        guard local.scheme == "http", local.host == "127.0.0.1",
              let port = local.port, (1...65535).contains(port),
              local.user == nil, local.password == nil, local.fragment == nil, local.query == nil,
              ["", "/"].contains(local.path), UUID(uuidString: ready.token) != nil else {
            throw OPLError.invalidEndpoint
        }
        let root = descriptor.deletingLastPathComponent().standardizedFileURL
        let proof = URL(fileURLWithPath: ready.proof).standardizedFileURL
        guard root.lastPathComponent.hasPrefix("lifting-http-contract-"), descriptor.lastPathComponent == "ready.json",
              proof.deletingLastPathComponent() == root, proof.lastPathComponent == "executed.json" else {
            throw OPLError.invalidEndpoint
        }
        // Fixed expected digest for the labeled 54-row CSV, independent of the returned envelope.
        let version = "138922c1db46f7d23eb0a407431da4baad5450ca430eb25912787fb86bd49296"
        XCTAssertEqual(ready.version, version)
        let transport = LoopbackContractTransport(port: port)
        for rejected in ["https://other.invalid/dataset", "http://contract.fixture.invalid/dataset",
            "https://user:password@contract.fixture.invalid/dataset", "https://contract.fixture.invalid/dataset#fragment",
            "https://contract.fixture.invalid:443/dataset"] {
            do { _ = try await transport.get(try XCTUnwrap(URL(string: rejected))); XCTFail("Unexpected origin accepted") }
            catch OPLError.invalidEndpoint {} catch { XCTFail("Unexpected adapter error: \(error)") }
        }
        let cache = OPLDiskCache(directory: root.appendingPathComponent("swift-cache", isDirectory: true))
        let repository = try OPLRepository(baseURL: XCTUnwrap(URL(string: "https://contract.fixture.invalid")),
            transport: transport, cache: cache)
        let metadata = try await repository.dataset(requireOnline: true)
        XCTAssertFalse(metadata.offline); XCTAssertNil(metadata.notice)
        XCTAssertEqual(metadata.value.dataset?.version, version)
        XCTAssertEqual(metadata.value.dataset?.rows, 54); XCTAssertEqual(metadata.value.dataset?.lifters, 29)
        XCTAssertEqual(metadata.value.validation?.version, version)
        XCTAssertEqual(metadata.value.statusMatchesDataset, true)
        XCTAssertEqual(metadata.value.sourceDate, "2025-01-01")
        XCTAssertEqual(metadata.value.status.lastSuccessfulCheckAt, "2025-01-04T00:00:00.123Z")
        XCTAssertEqual(metadata.value.status.nextCheckAt, "2025-01-04T06:00:00.123Z")
        XCTAssertNotNil(OPLDataset.date(metadata.value.validation?.validatedAt))
        XCTAssertTrue(metadata.value.sourceStale); XCTAssertTrue(metadata.value.checkStale)
        XCTAssertTrue(metadata.value.sourceIsStale()); XCTAssertTrue(metadata.value.checkIsStale())

        let search = OPLQuery(path: "lifters", parameters: ["q": "fixture"])
        let first = try await repository.page(search, version: version, as: OPLLifter.self)
        XCTAssertFalse(first.offline); XCTAssertEqual(first.value.version, version)
        XCTAssertEqual(first.value.results.count, 25)
        let last = try await repository.page(search, version: version,
            cursor: XCTUnwrap(first.value.nextCursor), as: OPLLifter.self)
        XCTAssertFalse(last.offline); XCTAssertEqual(last.value.version, version)
        XCTAssertEqual(last.value.results.count, 4); XCTAssertNil(last.value.nextCursor)
        let lifters = first.value.results + last.value.results
        let extraNames = (1...22).map { String(format: "Fixture Extra %02d", $0) }
        XCTAssertEqual(lifters.map(\.name), ["Fixture Alice #1", "Fixture Alice #2", "Fixture Bob", "Fixture DQ"]
            + extraNames + ["Fixture Failed", "Fixture Removed Casey", "Fixture Unofficial"])
        XCTAssertEqual(Set(lifters.map(\.lifterID)).count, 29)
        let alice = try XCTUnwrap(lifters.first { $0.name == "Fixture Alice #1" })
        XCTAssertEqual(alice.lifterID, "Rml4dHVyZSBBbGljZSAjMQ")

        // Profile is exact search identity plus history; no separate profile API exists.
        let historyQuery = OPLQuery(path: "lifters/\(alice.lifterID)/results")
        let historyFirst = try await repository.page(historyQuery, version: version, as: OPLResult.self)
        let historyLast = try await repository.page(historyQuery, version: version,
            cursor: XCTUnwrap(historyFirst.value.nextCursor), as: OPLResult.self)
        XCTAssertFalse(historyFirst.offline); XCTAssertFalse(historyLast.offline)
        XCTAssertEqual(historyFirst.value.version, version); XCTAssertEqual(historyLast.value.version, version)
        XCTAssertEqual(historyFirst.value.results.count, 25); XCTAssertEqual(historyLast.value.results.count, 1)
        XCTAssertNil(historyLast.value.nextCursor)
        let history = historyFirst.value.results + historyLast.value.results
        XCTAssertTrue(history.allSatisfy { $0.name == "Fixture Alice #1" && $0.lifterID == alice.lifterID })
        XCTAssertEqual(Set(history.map(\.rowID)).count, 26)
        XCTAssertEqual(history.map(\.date), ["2025-01-01", "2024-01-01"]
            + (1...24).reversed().map { String(format: "2023-01-%02d", $0) })
        XCTAssertEqual(history.map(\.total), [500.0, 450.0] + (276...299).map { Optional(Double($0)) })
        XCTAssertNil(history.first?.squat)
        XCTAssertEqual(history.last?.squat, -100); XCTAssertNil(history.last?.bench)
        XCTAssertEqual(history.last?.meet, "Synthetic, meet\nwith quoted text")

        let rankingsQuery = OPLQuery(path: "rankings", parameters: ["sex": "F", "equipment": "Raw", "event": "SBD"])
        let rankingFirst = try await repository.page(rankingsQuery, version: version, as: OPLResult.self)
        let rankingLast = try await repository.page(rankingsQuery, version: version,
            cursor: XCTUnwrap(rankingFirst.value.nextCursor), as: OPLResult.self)
        XCTAssertFalse(rankingFirst.offline); XCTAssertFalse(rankingLast.offline)
        XCTAssertEqual(rankingFirst.value.version, version); XCTAssertEqual(rankingLast.value.version, version)
        XCTAssertEqual(rankingFirst.value.results.count, 25); XCTAssertEqual(rankingLast.value.results.count, 1)
        XCTAssertNil(rankingLast.value.nextCursor)
        XCTAssertEqual(rankingFirst.value.label, "Best performance per source lifter name in this filtered dataset; not ratified records.")
        let ranked = rankingFirst.value.results + rankingLast.value.results
        XCTAssertEqual(ranked.map(\.name), ["Fixture Removed Casey", "Fixture Alice #1", "Fixture Alice #2", "Fixture Bob"] + extraNames)
        XCTAssertEqual(ranked.map(\.total), [520.0, 500.0, 490.0, 480.0] + (378...399).reversed().map { Optional(Double($0)) })
        XCTAssertEqual(Set(ranked.map(\.lifterID)).count, 26)
        let openClass = try await repository.page(OPLQuery(path: "rankings", parameters:
            ["sex": "F", "equipment": "Raw", "event": "SBD", "weightClass": "+"]), version: version, as: OPLResult.self)
        XCTAssertEqual(openClass.value.results.map(\.name), ["Fixture Alice #2"])
        XCTAssertEqual(openClass.value.results.first?.weightClass, "+")
        let unknown = String(repeating: "0", count: 64)
        do { _ = try await repository.page(search, version: unknown, as: OPLLifter.self); XCTFail("Unserved version accepted") }
        catch OPLError.versionUnavailable {} catch { XCTFail("Real 409 failed classification: \(error)") }

        // Runner requires this proof AND successful XCTest exit, so absent/skipped tests fail CI.
        try JSONSerialization.data(withJSONObject: ["token": ready.token,
            "method": "testActualNodeHTTPContract", "version": version]).write(to: proof, options: .atomic)
    }
}
#endif
