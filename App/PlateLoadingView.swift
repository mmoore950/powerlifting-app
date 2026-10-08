import SwiftUI
import LiftingCore

@MainActor
struct PlateLoadingView: View {
    @ObservedObject var model: LoadingModel
    @State private var configuring = false
    @FocusState private var editingWeight: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MAKE EVERY PLATE COUNT").font(.caption.weight(.bold)).foregroundStyle(.mint)
                        Text("Your bar. Your load.").font(.largeTitle.bold())
                    }
                    Picker("Calculator", selection: $model.mode) {
                        ForEach(LoadingModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if let notice = model.settingsNotice {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(notice).font(.footnote).foregroundStyle(.orange)
                            Button("Dismiss") { model.dismissSettingsNotice() }
                        }
                    }
                    HStack {
                        unitPicker("Show weight in", value: model.displayUnit, setter: { model.setDisplayUnit($0) })
                        unitPicker("Available plates", value: model.plateUnit, setter: { model.setPlateUnit($0) })
                    }
                    if model.mode == .load {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TOTAL TARGET").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline) {
                                TextField("Weight", text: Binding(get: { model.targetText }, set: model.editTarget))
                                    .keyboardType(.decimalPad).font(.system(size: 48, weight: .bold, design: .rounded))
                                    .focused($editingWeight).accessibilityLabel("Target total weight in \(model.displayUnit.symbol)")
                                Text(model.displayUnit.symbol).font(.title2).foregroundStyle(.secondary)
                            }
                        }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    } else {
                        Text("Add plates per side. Both sides, the bar, and two collars are included.")
                            .foregroundStyle(.secondary)
                        ForEach(model.inventory.entries) { entry in
                            Stepper(value: Binding(get: { model.counts[entry.milliUnits, default: 0] },
                                                   set: { model.select(entry, count: $0) }),
                                    in: 0...entry.availablePairs) {
                                Text("\(entry.weight(in: model.plateUnit).mass.formatted(in: model.plateUnit)) \(model.plateUnit.symbol) × \(model.counts[entry.milliUnits, default: 0]) / side")
                            }.accessibilityLabel("\(entry.weight(in: model.plateUnit).mass.formatted(in: model.plateUnit)) \(model.plateUnit.symbol) plates per side")
                                .accessibilityValue("\(model.counts[entry.milliUnits, default: 0]) pairs selected")
                                .accessibilityHint("Available pairs: \(entry.availablePairs). Changes both sides of the bar.")
                        }
                    }
                    if model.mode == .load, model.calculating { ProgressView("Finding a load…") }
                    if model.mode == .load, let error = model.error {
                        Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                            .accessibilityLabel("Error: \(error)")
                    }
                    if let solution = model.shownSolution {
                        solutionCard(solution)
                        if model.mode == .load, let result = model.result, !result.isExact {
                            alternatives(result)
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Equipment").font(.headline)
                        Text("Bar \(model.equipment.bar.formatted(in: model.displayUnit)) \(model.displayUnit.symbol) · collar \(model.equipment.collarEach.formatted(in: model.displayUnit)) \(model.displayUnit.symbol) each")
                        Text("Plate units and display units are independent. Changing either keeps the bar and collars at their physical weight.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Lift Toolkit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Equipment", systemImage: "slider.horizontal.3") { configuring = true }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editingWeight = false }
                }
            }
            .sheet(isPresented: $configuring) { EquipmentView(model: model) }
            .task { model.recalculate() }
        }.tint(.mint).preferredColorScheme(.dark)
    }

    private func unitPicker(_ label: String, value: WeightUnit,
                            setter: @escaping @MainActor @Sendable (WeightUnit) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Picker(label, selection: Binding(get: { value }, set: setter)) {
                ForEach(WeightUnit.allCases, id: \.self) { Text($0.symbol).tag($0) }
            }.pickerStyle(.segmented)
        }.frame(maxWidth: .infinity)
    }

    private func solutionCard(_ solution: LoadSolution) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.mode == .reverse ? "TOTAL ON THE BAR" : model.result?.isExact == true ? "EXACT LOAD" : "CLOSEST AVAILABLE")
                .font(.caption.weight(.bold)).foregroundStyle(.mint)
            Text("\(solution.total.formatted(in: model.displayUnit)) \(model.displayUnit.symbol)")
                .font(.largeTitle.bold()).minimumScaleFactor(0.6)
            Text("\(solution.total.formatted(in: model.displayUnit.other)) \(model.displayUnit.other.symbol)").foregroundStyle(.secondary)
            PlateDiagram(solution: solution)
            Text("PER SIDE").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            if solution.plates.isEmpty { Text("Bar + collars only") }
            ForEach(solution.plates, id: \.weight.milliUnits) { plate in
                HStack {
                    Text("\(plate.weight.mass.formatted(in: plate.weight.unit)) \(plate.weight.unit.symbol)")
                    Spacer()
                    Text("× \(plate.perSide)").monospacedDigit().bold()
                }.accessibilityElement(children: .ignore)
                    .accessibilityLabel("Per side: \(plate.perSide) plates of \(plate.weight.mass.formatted(in: plate.weight.unit)) \(plate.weight.unit.symbol)")
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private func alternatives(_ result: LoadingResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let difference = abs(result.closest.total.value(in: model.displayUnit) - result.requested.value(in: model.displayUnit))
            Text("Target is unavailable with this inventory.").font(.headline)
            Text("Closest is \(difference, specifier: "%.3f") \(model.displayUnit.symbol) \(result.closest.total < result.requested ? "below" : "above") your target.")
            Text(result.lower.map { "At or below: \($0.total.formatted(in: model.displayUnit)) \(model.displayUnit.symbol)" } ?? "No load at or below this target.")
            Text(result.upper.map { "At or above: \($0.total.formatted(in: model.displayUnit)) \(model.displayUnit.symbol)" } ?? "No load at or above this target.")
        }.font(.subheadline).foregroundStyle(.secondary)
    }
}

@MainActor
struct PlateDiagram: View {
    let solution: LoadSolution
    private var plates: [WeightAmount] {
        solution.plates.flatMap { Array(repeating: $0.weight, count: $0.perSide) }
    }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(.gray).frame(width: 38, height: 12)
                ForEach(Array(plates.enumerated()), id: \.offset) { _, plate in
                    let size = plate.mass.value(in: plate.unit)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(appearance(plate).fill)
                        .frame(width: 42, height: CGFloat(min(120, max(48, 48 + size * 2))))
                        .overlay { RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.6), lineWidth: 1) }
                        .overlay {
                            VStack(spacing: 2) {
                                Text(plate.mass.formatted(in: plate.unit)).minimumScaleFactor(0.5)
                                Text(plate.unit.symbol)
                            }.font(.caption2.bold()).foregroundStyle(appearance(plate).text)
                        }
                }
                RoundedRectangle(cornerRadius: 3).fill(.gray).frame(width: 28, height: 12)
            }.frame(height: 130)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plates on one side: " + (solution.plates.isEmpty ? "none" : solution.plates.map { "\($0.perSide) of \($0.weight.mass.formatted(in: $0.weight.unit)) \($0.weight.unit.symbol)" }.joined(separator: ", ")))
    }

    private func appearance(_ plate: WeightAmount) -> (fill: Color, text: Color) {
        guard plate.unit == .kilograms else {
            return (plate.milliUnits >= 25_000 ? Color(white: 0.18) : Color(white: 0.38), .white)
        }
        // IPF specifies these three sizes; smaller/custom colors are schematic choices.
        switch plate.milliUnits {
        case 25_000: return (.red, .white)
        case 20_000: return (.blue, .white)
        case 15_000: return (.yellow, .black)
        case 10_000: return (.green, .black)
        case 5_000: return (.white, .black)
        default: return (Color(white: 0.35), .white)
        }
    }
}
