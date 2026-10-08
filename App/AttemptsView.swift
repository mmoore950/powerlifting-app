import SwiftUI
import LiftingCore

@MainActor
struct AttemptsView: View {
    @ObservedObject var equipment: LoadingModel
    @State private var goal = MassEntry(200_000, unit: .kilograms)
    @State private var increment = MassEntry(2_500, unit: .kilograms)
    @State private var incrementUnit: WeightUnit = .kilograms
    @State private var opener = MassEntry(0, unit: .kilograms)
    @State private var second = MassEntry(0, unit: .kilograms)
    @State private var manual = false
    @State private var openerLow = 80
    @State private var openerHigh = 90
    @State private var secondLow = 90
    @State private var secondHigh = 97
    @StateObject private var runner = PlanRunner<AttemptPlan>()
    var body: some View {
        NavigationStack {
            Form {
                Section("Shared equipment") { SharedEquipmentControls(model: equipment) }
                Section("Competition equipment preset") {
                    Button("Use 20 kg bar, 2.5 kg collars & kg plates") {
                        do {
                            try equipment.configure(equipment: Equipment(bar: WeightAmount(milliUnits: 20_000, unit: .kilograms).mass,
                                                                        collarEach: WeightAmount(milliUnits: 2_500, unit: .kilograms).mass),
                                                    inventory: equipment.inventories[.kilograms]!)
                            equipment.setPlateUnit(.kilograms)
                        } catch { runner.fail(error) }
                    }
                    Text("Updates equipment in every tab. Uses your saved kg inventory; verify the equipment at your meet. A pound bar may not produce exact kg increment totals.").font(.footnote)
                }
                Section("Work back from your third") {
                    Text("Desired third · \(equipment.displayUnit.symbol)").font(.caption).foregroundStyle(.secondary)
                    TextField("Desired third (\(equipment.displayUnit.symbol))", text: Binding(get: { goal.text }, set: {
                        goal.edit($0, unit: equipment.displayUnit); runner.clear()
                    })).keyboardType(.decimalPad).accessibilityLabel("Desired third attempt in \(equipment.displayUnit.symbol)")
                    Text("Your goal is aspirational. These percentages do not prove that you can lift it. Choose attempts using demonstrated strength and how meet day is going.").font(.footnote)
                    Picker("Increment unit", selection: $incrementUnit) {
                        ForEach(WeightUnit.allCases, id: \.self) { Text($0.symbol).tag($0) }
                    }.pickerStyle(.segmented)
                    Text("Total attempt increment · \(incrementUnit.symbol)").font(.caption).foregroundStyle(.secondary)
                    TextField("Total increment (\(incrementUnit.symbol))", text: Binding(get: { increment.text }, set: {
                        increment.edit($0, unit: incrementUnit); runner.clear()
                    })).keyboardType(.decimalPad).accessibilityLabel("Total attempt increment in \(incrementUnit.symbol)")
                    Text("Weights must be whole multiples of this total increment. Default is 2.5 kg for ordinary IPF attempts; verify your federation's rules. Record exceptions are not modeled.").font(.footnote)
                }
                Section("Editable percentage ranges") {
                    Stepper("Opener low: \(openerLow)%", value: $openerLow, in: 1...99)
                    Stepper("Opener high: \(openerHigh)%", value: $openerHigh, in: 1...99)
                    Stepper("Second low: \(secondLow)%", value: $secondLow, in: 1...99)
                    Stepper("Second high: \(secondHigh)%", value: $secondHigh, in: 1...99)
                    Text("Starts at 80–90% and 90–97% of the loadable third. Suggestions choose loadable weights near each range midpoint. This is a planning preset, not a strength forecast.").font(.footnote)
                    Toggle("Use my opener and second", isOn: $manual)
                    if manual {
                        Text("My opener · \(equipment.displayUnit.symbol)").font(.caption).foregroundStyle(.secondary)
                        TextField("My opener (\(equipment.displayUnit.symbol))", text: Binding(get: { opener.text }, set: {
                            opener.edit($0, unit: equipment.displayUnit); runner.clear()
                        })).keyboardType(.decimalPad).accessibilityLabel("My opener in \(equipment.displayUnit.symbol)")
                        Text("My second · \(equipment.displayUnit.symbol)").font(.caption).foregroundStyle(.secondary)
                        TextField("My second (\(equipment.displayUnit.symbol))", text: Binding(get: { second.text }, set: {
                            second.edit($0, unit: equipment.displayUnit); runner.clear()
                        })).keyboardType(.decimalPad).accessibilityLabel("My second attempt in \(equipment.displayUnit.symbol)")
                        Text("Manual weights may be outside the preset ranges. They must be exactly loadable and ordered.").font(.footnote)
                    }
                    Button("Plan three attempts") { plan() }
                    if runner.busy { ProgressView("Planning…") }
                    if let error = runner.error { InputErrorView(message: error) }
                }
                if let plan = runner.value {
                    Section("Loadable attempt plan") {
                        if plan.goal != plan.third.total {
                            Text("Desired third is unavailable on this inventory/increment. Planned third is the greatest load at or below the goal.").foregroundStyle(.orange)
                        }
                        Text("Loadable opener range: \(rangeLabel(plan.openerRange))").font(.footnote)
                        Text("Loadable second range: \(rangeLabel(plan.secondRange))").font(.footnote)
                        PlannedLoadView(title: "1 · Opener", load: plan.opener, unit: equipment.displayUnit)
                        PlannedLoadView(title: "2 · Second", load: plan.second, unit: equipment.displayUnit)
                        PlannedLoadView(title: "3 · Planned third", load: plan.third, unit: equipment.displayUnit)
                    }
                }
            }.navigationTitle("Meet attempts")
                .onAppear { displayInputs() }
                .onChange(of: equipment.displayUnit) { _, _ in displayInputs() }
                .onChange(of: equipment.settingsRevision) { _, _ in runner.clear() }
                .onChange(of: incrementUnit) { _, unit in increment.display(in: unit) }
                .onChange(of: [openerLow, openerHigh, secondLow, secondHigh]) { _, _ in runner.clear() }
                .onChange(of: manual) { _, enabled in
                    if enabled, let plan = runner.value {
                        opener = MassEntry(mass: plan.opener.total, unit: equipment.displayUnit)
                        second = MassEntry(mass: plan.second.total, unit: equipment.displayUnit)
                    }
                    runner.clear()
                }
                .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { dismissKeyboard() } } }
        }
    }
    private func displayInputs() {
        goal.display(in: equipment.displayUnit); opener.display(in: equipment.displayUnit); second.display(in: equipment.displayUnit)
    }
    private func rangeLabel(_ loads: [LoadSolution]) -> String {
        guard let first = loads.first, let last = loads.last else { return "none in preset range" }
        return "\(first.total.formatted(in: equipment.displayUnit))–\(last.total.formatted(in: equipment.displayUnit)) \(equipment.displayUnit.symbol) (\(loads.count) available choices)"
    }
    private func plan() {
        do {
            let third = try goal.positive(), increment = try increment.positive()
            let ranges = try AttemptRanges(openerLow: openerLow, openerHigh: openerHigh, secondLow: secondLow, secondHigh: secondHigh)
            let first: Mass?
            let next: Mass?
            if manual { first = try opener.positive(); next = try second.positive() }
            else { first = nil; next = nil }
            let bar = equipment.equipment, inventory = equipment.inventory
            runner.run { try AttemptPlanner.plan(thirdGoal: third, increment: increment, ranges: ranges,
                                                equipment: bar, inventory: inventory, openerOverride: first, secondOverride: next) }
        } catch { runner.fail(error) }
    }
}
