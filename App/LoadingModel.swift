import Foundation
import SwiftUI
import LiftingCore

@MainActor
final class LoadingModel: ObservableObject {
    enum Mode: String, CaseIterable { case load = "Load", reverse = "Reverse" }
    @Published var mode: Mode = .load
    @Published private(set) var displayUnit: WeightUnit = .pounds
    @Published private(set) var plateUnit: WeightUnit = .pounds
    @Published private(set) var targetText = "225"
    @Published private(set) var equipment = Equipment(bar: try! WeightAmount(milliUnits: 45_000, unit: .pounds).mass)
    @Published private(set) var inventories: [WeightUnit: PlateInventory] = [
        .pounds: .standard(.pounds), .kilograms: .standard(.kilograms)
    ]
    @Published private(set) var selections: [WeightUnit: [Int64: Int]] = [:]
    @Published private(set) var result: LoadingResult?
    @Published private(set) var error: String?
    @Published private(set) var calculating = false
    @Published private(set) var settingsNotice: String?
    @Published private(set) var settingsRevision = 0
    private let store: PreferencesStore
    private var target: Mass? = try! WeightAmount(milliUnits: 225_000, unit: .pounds).mass
    private var lastValidTarget = AppPreferences.defaults.target
    private var request: Task<Void, Never>?
    private var calculation: Task<LoadingResult, Error>?
    private var generation = 0

    init(store: PreferencesStore = PreferencesStore()) {
        self.store = store
        let saved = store.load()
        let preferences = saved.preferences
        equipment = preferences.equipment
        inventories = [.kilograms: preferences.kilogramInventory, .pounds: preferences.poundInventory]
        displayUnit = preferences.displayUnit
        plateUnit = preferences.plateUnit
        target = preferences.target
        lastValidTarget = preferences.target
        targetText = preferences.target.formatted(in: displayUnit)
        settingsNotice = saved.notice
    }

    var inventory: PlateInventory { inventories[plateUnit]! }
    var counts: [Int64: Int] { selections[plateUnit, default: [:]] }
    var reverseSolution: LoadSolution? {
        try? PlateLoader.reverse(equipment: equipment, inventory: inventory, counts: counts)
    }
    var shownSolution: LoadSolution? { mode == .load ? result?.closest : reverseSolution }

    func editTarget(_ text: String) {
        targetText = text
        do {
            let decimal = Locale.current.decimalSeparator ?? "."
            target = try WeightAmount.parse(text.replacingOccurrences(of: decimal, with: "."), unit: displayUnit).mass
            if let target { lastValidTarget = target }
            persist()
            recalculate()
        } catch {
            cancelCalculation()
            target = nil
            result = nil
            self.error = error.localizedDescription
        }
    }

    func setDisplayUnit(_ unit: WeightUnit) {
        displayUnit = unit
        // Never parse the rounded display back into physical mass.
        if let target { targetText = target.formatted(in: unit) }
        persist()
    }

    func setPlateUnit(_ unit: WeightUnit) {
        plateUnit = unit
        settingsRevision += 1
        persist()
        recalculate()
    }

    func select(_ entry: PlateEntry, count: Int) {
        guard (0...entry.availablePairs).contains(count) else { return }
        var selected = counts
        selected[entry.milliUnits] = count
        selections[plateUnit] = selected
    }

    func configure(equipment: Equipment, inventory: PlateInventory) throws {
        _ = try equipment.baseMass
        _ = try PlateLoader.reverse(equipment: equipment, inventory: inventory, counts: [:])
        self.equipment = equipment
        inventories[inventory.unit] = inventory
        var selected = selections[inventory.unit, default: [:]]
        let known = Set(inventory.entries.map(\.milliUnits))
        selected = selected.filter { known.contains($0.key) }
        for entry in inventory.entries {
            selected[entry.milliUnits] = min(selected[entry.milliUnits, default: 0], entry.availablePairs)
        }
        selections[inventory.unit] = selected
        settingsRevision += 1
        persist()
        recalculate()
    }

    func dismissSettingsNotice() { settingsNotice = nil }

    private func persist() {
        do {
            let value = try AppPreferences(equipment: equipment, kilogramInventory: inventories[.kilograms]!,
                                           poundInventory: inventories[.pounds]!, displayUnit: displayUnit,
                                           plateUnit: plateUnit, target: target ?? lastValidTarget)
            try store.save(value)
        } catch { settingsNotice = "Settings could not be saved. \(error.localizedDescription)" }
    }

    func recalculate() {
        cancelCalculation()
        guard let target else { return }
        result = nil
        error = nil
        calculating = true
        let token = generation
        let equipment = equipment
        let inventory = inventory
        request = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                try Task.checkCancellation()
                let work = Task.detached(priority: .userInitiated) {
                    try PlateLoader.load(target: target, equipment: equipment, inventory: inventory)
                }
                self?.calculation = work
                let value = try await work.value
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.result = value
                self.calculating = false
            } catch is CancellationError {
                // A newer input owns the screen now.
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                self.calculating = false
            }
        }
    }

    private func cancelCalculation() {
        generation += 1
        request?.cancel()
        calculation?.cancel()
        calculating = false
    }
}
