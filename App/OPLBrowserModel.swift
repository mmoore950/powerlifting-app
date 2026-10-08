import Foundation
import SwiftUI
import LiftingCore

@MainActor
final class OPLBrowserModel: ObservableObject {
    @Published private(set) var metadata: OPLDelivery<OPLDataset>?
    @Published private(set) var repository: OPLRepository?
    @Published private(set) var revision = 0
    @Published private(set) var refreshing = false
    @Published private(set) var error: String?
    @Published private(set) var endpoint = UserDefaults.standard.string(forKey: "opl.serviceURL") ?? ""
    private var generation = 0
    private var refreshGeneration = 0
    var version: String? { metadata?.value.dataset?.version }

    func start() async {
        guard repository == nil, !endpoint.isEmpty else { return }
        await connect(endpoint)
    }
    func connect(_ text: String) async {
        do {
            guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw OPLError.invalidEndpoint
            }
            let root = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true).appendingPathComponent("OpenPowerlifting", isDirectory: true)
            let client = try OPLRepository(baseURL: url, cache: OPLDiskCache(directory: root))
            generation += 1
            repository = client; endpoint = url.absoluteString; metadata = nil; error = nil; revision += 1
            UserDefaults.standard.set(endpoint, forKey: "opl.serviceURL")
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard let repository else { return }
        let connection = generation
        refreshGeneration += 1
        let request = refreshGeneration
        refreshing = true
        defer { if request == refreshGeneration { refreshing = false } }
        do {
            let delivery = try await repository.dataset()
            guard connection == generation, request == refreshGeneration, !Task.isCancelled else { return }
            metadata = delivery; error = nil; revision += 1
        } catch {
            guard connection == generation, request == refreshGeneration, !(error is CancellationError) else { return }
            self.error = error.localizedDescription
        }
    }
    func adoptRecovery(_ delivery: OPLDelivery<OPLDataset>, from client: OPLRepository) {
        guard let repository, repository === client, !delivery.offline else { return }
        // Supersede an older in-flight metadata refresh and tell other pages to change versions.
        refreshGeneration += 1; refreshing = false
        metadata = delivery; error = nil; revision += 1
    }
}

@MainActor
final class OPLPageStore<Item: Codable & Identifiable & Sendable>: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var cursor: String?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var offline = false
    @Published private(set) var savedAt: Date?
    @Published private(set) var notice: String?
    @Published private(set) var loadedVersion: String?
    private var generation = 0
    private var client: OPLRepository?
    private var query: OPLQuery?
    private var recoveryClient: OPLRepository?
    private var recoveryQuery: OPLQuery?
    private var recoveryAttempted = false
    private var skipResetVersion: String?
    private var pendingRecovery: OPLDelivery<OPLDataset>?
    private var failedCursor: String?
    private var adoptDataset: (@MainActor (OPLDelivery<OPLDataset>, OPLRepository) -> Void)?

    func reset(client: OPLRepository?, version: String?, query: OPLQuery?,
        adoptDataset: (@MainActor (OPLDelivery<OPLDataset>, OPLRepository) -> Void)? = nil,
        delayNanoseconds: UInt64 = 0) async {
        let sameClient: Bool
        if let client, let recoveryClient { sameClient = client === recoveryClient } else { sameClient = false }
        let sameQuery = sameClient && recoveryQuery == query
        // Adoption updates the shared metadata revision. Preserve this already restarted page/error.
        if sameQuery, let skipResetVersion, skipResetVersion == version {
            self.skipResetVersion = nil; return
        }
        if !sameQuery { recoveryAttempted = false; recoveryClient = client; recoveryQuery = query }
        generation += 1
        let request = generation
        self.client = client; self.query = query; loadedVersion = version; self.adoptDataset = adoptDataset
        skipResetVersion = nil; pendingRecovery = nil; failedCursor = nil
        items = []; cursor = nil; error = nil; offline = false; savedAt = nil; notice = nil; loading = false
        guard client != nil, version != nil, query != nil else { return }
        if delayNanoseconds > 0 {
            loading = true
            do { try await Task.sleep(nanoseconds: delayNanoseconds) }
            catch { if request == generation { loading = false }; return }
            guard request == generation, !Task.isCancelled else {
                if request == generation { loading = false }; return
            }
        }
        await fetch(cursor: nil)
    }
    func more() async {
        guard !loading, let cursor else { return }
        await fetch(cursor: cursor)
    }
    func retry() async {
        guard !loading, error != nil else { return }
        recoveryAttempted = false // Explicit human retry grants one new recovery transaction.
        await fetch(cursor: failedCursor)
    }
    private func expired(request: Int) {
        guard request == generation, !Task.isCancelled else { return }
        recoveryAttempted = true; items = []; cursor = nil; savedAt = nil; offline = false
        failedCursor = nil; notice = "The previous result version expired. Checking current data."
    }
    private func recoveredDataset(_ delivery: OPLDelivery<OPLDataset>, request: Int) {
        guard request == generation, !Task.isCancelled else { return }
        pendingRecovery = delivery; loadedVersion = delivery.value.dataset?.version
    }
    private func fetch(cursor requestedCursor: String?) async {
        guard let client, let query, let loadedVersion else { return }
        let request = generation
        loading = true; error = nil; failedCursor = requestedCursor
        let allowRecovery = !recoveryAttempted
        defer {
            if request == generation {
                loading = false
                if let delivery = pendingRecovery {
                    pendingRecovery = nil
                    if !Task.isCancelled { skipResetVersion = self.loadedVersion; adoptDataset?(delivery, client) }
                }
            }
        }
        do {
            let attempt = try await client.recoveringPage(query, version: loadedVersion, cursor: requestedCursor,
                as: Item.self, allowRecovery: allowRecovery,
                onExpiration: { [weak self] in await self?.expired(request: request) },
                onDataset: { [weak self] delivery in await self?.recoveredDataset(delivery, request: request) })
            guard request == generation, !Task.isCancelled else { return }
            let result = attempt.page
            if attempt.restarted { items = []; cursor = nil }
            self.loadedVersion = result.value.version
            var ids = Set(items.map(\.id))
            items.append(contentsOf: result.value.results.filter { ids.insert($0.id).inserted })
            cursor = result.value.nextCursor; offline = offline || result.offline
            savedAt = result.savedAt; notice = result.notice ?? (attempt.restarted ? "Results restarted with current data." : nil); error = nil
            failedCursor = nil
        } catch {
            guard request == generation, !(error is CancellationError) else { return }
            self.error = error.localizedDescription
            if recoveryAttempted, items.isEmpty { notice = nil }
        }
    }
}
