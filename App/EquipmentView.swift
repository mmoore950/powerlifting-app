import SwiftUI
import LiftingCore

@MainActor
struct EquipmentView: View {
    @ObservedObject var model: LoadingModel
    @Environment(\.dismiss) private var dismiss
    @State private var bar = ""
    @State private var collar = ""
    @State private var pairs: [Int64: Int] = [:]
    @State private var entries: [PlateEntry] = []
    @State private var newSize = ""
    @State private var error: String?
    @State private var originalBar = ""
    @State private var originalCollar = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Equipment in \(model.displayUnit.symbol)") {
                    TextField("Bar weight", text: $bar).keyboardType(.decimalPad)
                    TextField("One collar weight", text: $collar).keyboardType(.decimalPad)
                    Text("Two collars are included. Enter 0 to use no collars.").font(.footnote)
                }
                Section("Available \(model.plateUnit.symbol) plate pairs") {
                    ForEach(entries) { entry in
                        Stepper(value: Binding(get: { pairs[entry.milliUnits, default: 0] },
                                               set: { pairs[entry.milliUnits] = $0 }), in: 0...40) {
                            Text("\(entry.weight(in: model.plateUnit).mass.formatted(in: model.plateUnit)) \(model.plateUnit.symbol) · \(pairs[entry.milliUnits, default: 0]) pairs")
                        }
                    }.onDelete { offsets in entries.remove(atOffsets: offsets) }
                    HStack {
                        TextField("Custom plate size", text: $newSize).keyboardType(.decimalPad)
                        Button("Add") { addPlate() }
                    }
                    Text("A pair is one plate on each side. Up to 16 sizes and 40 pairs total. Reducing availability also reduces selected reverse plates.").font(.footnote)
                }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
            }
            .navigationTitle("Equipment").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                bar = model.equipment.bar.formatted(in: model.displayUnit)
                collar = model.equipment.collarEach.formatted(in: model.displayUnit)
                originalBar = bar
                originalCollar = collar
                entries = model.inventory.entries
                pairs = Dictionary(uniqueKeysWithValues: entries.map { ($0.milliUnits, $0.availablePairs) })
            }
        }
    }

    private func parse(_ text: String) throws -> WeightAmount {
        try WeightAmount.parse(text.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: "."), unit: model.displayUnit)
    }
    private func addPlate() {
        do {
            let amount = try WeightAmount.parse(newSize.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: "."), unit: model.plateUnit)
            guard !entries.contains(where: { $0.milliUnits == amount.milliUnits }) else { throw LoadingError.duplicatePlate }
            guard entries.count < 16 else { throw LoadingError.invalidInventory }
            let entry = try PlateEntry(milliUnits: amount.milliUnits, availablePairs: 1)
            entries.append(entry)
            entries.sort { $0.milliUnits > $1.milliUnits }
            pairs[entry.milliUnits] = 1
            newSize = ""
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func save() {
        do {
            // Preserve exact physical mass when an unchanged converted field is saved.
            let barMass = try (bar == originalBar ? model.equipment.bar : parse(bar).mass)
            let collarMass = try (collar == originalCollar ? model.equipment.collarEach : parse(collar).mass)
            let inventory = try PlateInventory(unit: model.plateUnit, entries: entries.map {
                try PlateEntry(milliUnits: $0.milliUnits, availablePairs: pairs[$0.milliUnits, default: 0])
            })
            try model.configure(equipment: Equipment(bar: barMass, collarEach: collarMass), inventory: inventory)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
