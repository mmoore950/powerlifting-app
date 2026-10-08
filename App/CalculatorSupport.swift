import SwiftUI
import LiftingCore

struct MassEntry {
    private(set) var text: String
    private(set) var mass: Mass?
    init(_ milliUnits: Int64, unit: WeightUnit) {
        let value = try! WeightAmount(milliUnits: milliUnits, unit: unit).mass
        mass = value; text = value.formatted(in: unit)
    }
    init(mass: Mass, unit: WeightUnit) { self.mass = mass; text = mass.formatted(in: unit) }
    mutating func edit(_ value: String, unit: WeightUnit) {
        text = value
        mass = try? WeightAmount.parse(value.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: "."), unit: unit).mass
    }
    mutating func display(in unit: WeightUnit) {
        if let mass { text = mass.formatted(in: unit) }
    }
    func positive() throws -> Mass {
        guard let mass, mass > .zero else { throw TrainingError.invalidWeight }
        return mass
    }
}

struct InputErrorView: View {
    let message: String
    var body: some View {
        Label { Text(message) } icon: { Image(systemName: "exclamationmark.circle") }
            .foregroundStyle(.orange)
            .accessibilityLabel("Error: \(message)")
    }
}

@MainActor
final class PlanRunner<Value: Sendable>: ObservableObject {
    @Published private(set) var value: Value?
    @Published private(set) var error: String?
    @Published private(set) var busy = false
    private var request: Task<Void, Never>?
    private var work: Task<Value, Error>?
    private var generation = 0
    func clear() {
        generation += 1; request?.cancel(); work?.cancel()
        value = nil; error = nil; busy = false
    }
    func fail(_ error: Error) { clear(); self.error = error.localizedDescription }
    func run(_ operation: @escaping @Sendable () throws -> Value) {
        clear(); busy = true
        let token = generation
        request = Task { [weak self] in
            let work = Task.detached(priority: .userInitiated, operation: operation)
            self?.work = work
            do {
                let value = try await work.value
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.value = value; self.busy = false
            } catch is CancellationError {} catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.error = error.localizedDescription; self.busy = false
            }
        }
    }
}

@MainActor
struct SharedEquipmentControls: View {
    @ObservedObject var model: LoadingModel
    @State private var showingEquipment = false
    @State private var showingNotices = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Display weight", selection: Binding(get: { model.displayUnit }, set: model.setDisplayUnit)) {
                ForEach(WeightUnit.allCases, id: \.self) { Text("Show \($0.symbol)").tag($0) }
            }.pickerStyle(.segmented)
            Picker("Plate inventory", selection: Binding(get: { model.plateUnit }, set: model.setPlateUnit)) {
                ForEach(WeightUnit.allCases, id: \.self) { Text("\($0.symbol) plates").tag($0) }
            }.pickerStyle(.segmented)
            Button("Shared bar, collars & inventory") { showingEquipment = true }
            Text("Bar \(model.equipment.bar.formatted(in: model.displayUnit)) \(model.displayUnit.symbol); collars \(model.equipment.collarEach.formatted(in: model.displayUnit)) \(model.displayUnit.symbol) each")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open-source notices") { showingNotices = true }.font(.caption)
        }.sheet(isPresented: $showingEquipment) { EquipmentView(model: model) }
            .sheet(isPresented: $showingNotices) { NoticesView() }
    }
}

@MainActor
struct NoticesView: View {
    @Environment(\.dismiss) private var dismiss
    private var notices: String {
        guard let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Open-source notice resource is missing. See THIRD_PARTY_NOTICES.md in the project source."
        }
        return text
    }
    var body: some View {
        NavigationStack {
            ScrollView { Text(notices).font(.footnote).textSelection(.enabled).padding() }
                .navigationTitle("Open-source notices")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

@MainActor
struct PlannedLoadView: View {
    let title: String
    let load: LoadSolution
    let unit: WeightUnit
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text("\(load.total.formatted(in: unit)) \(unit.symbol)").font(.title2.bold())
            Text("\(load.total.formatted(in: unit.other)) \(unit.other.symbol)").font(.caption).foregroundStyle(.secondary)
            PlateDiagram(solution: load)
            Text(load.plates.isEmpty ? "Bar + collars only" : "Per side: " + load.plates.map {
                "\($0.weight.mass.formatted(in: $0.weight.unit)) \($0.weight.unit.symbol) × \($0.perSide)"
            }.joined(separator: " + ")).font(.caption)
        }.padding(.vertical, 8)
    }
}
