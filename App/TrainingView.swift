import SwiftUI
import UIKit
import LiftingCore

@MainActor
struct TrainingView: View {
    @ObservedObject var equipment: LoadingModel
    @State private var performed = MassEntry(100_000, unit: .kilograms)
    @State private var top = MassEntry(140_000, unit: .kilograms)
    @State private var reps = "5"
    @State private var lift = "Squat"
    @State private var topReps = 3
    @State private var steps = WarmupStep.standard
    @State private var estimates: [OneRepFormula: Mass] = [:]
    @State private var estimateError: String?
    @StateObject private var runner = PlanRunner<WarmupPlan>()
    var body: some View {
        NavigationStack {
            Form {
                Section("Shared equipment") { SharedEquipmentControls(model: equipment) }
                Section("Estimated one-rep max") {
                    Text("Completed set weight · \(equipment.displayUnit.symbol)").font(.caption).foregroundStyle(.secondary)
                    TextField("Completed set weight (\(equipment.displayUnit.symbol))", text: Binding(get: { performed.text }, set: {
                        performed.edit($0, unit: equipment.displayUnit); estimates = [:]; estimateError = nil
                    })).keyboardType(.decimalPad).accessibilityLabel("Completed set weight in \(equipment.displayUnit.symbol)")
                    LabeledContent("Completed reps (1–10)") {
                        TextField("Reps", text: $reps).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .accessibilityLabel("Completed repetitions, from 1 to 10")
                    }
                        .onChange(of: reps) { _, _ in estimates = [:]; estimateError = nil }
                    Button("Estimate both formulas") { estimate() }
                    if let estimateError { InputErrorView(message: estimateError) }
                    ForEach(OneRepFormula.allCases, id: \.self) { formula in
                        if let mass = estimates[formula] {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(formula.rawValue): \(mass.formatted(in: equipment.displayUnit, fractionDigits: 1)) \(equipment.displayUnit.symbol)").font(.headline)
                                Text(formula.equation).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("An estimate from a completed set near your repetition limit, not a proven maximum or a prescription. Effort and technique change the estimate. One completed rep returns that weight unchanged; this tool supports 1–10 reps.").font(.footnote)
                }
                Section("Today's warm-up") {
                    Picker("Lift", selection: $lift) { ForEach(["Squat", "Bench", "Deadlift"], id: \.self) { Text($0) } }
                    Text("Top-set target · \(equipment.displayUnit.symbol)").font(.caption).foregroundStyle(.secondary)
                    TextField("Top-set target (\(equipment.displayUnit.symbol))", text: Binding(get: { top.text }, set: {
                        top.edit($0, unit: equipment.displayUnit); runner.clear()
                    })).keyboardType(.decimalPad).accessibilityLabel("Top-set target in \(equipment.displayUnit.symbol)")
                    Stepper("Top-set reps: \(topReps)", value: $topReps, in: 1...20)
                    Text("Edit the percentage and reps for each warm-up. Percentages refer to the actual loadable top set.").font(.footnote)
                    ForEach(steps.indices, id: \.self) { index in
                        VStack(alignment: .leading) {
                            Stepper("Set \(index + 1): \(steps[index].percent)%", value: $steps[index].percent, in: 1...99)
                            Stepper("Reps: \(steps[index].reps)", value: $steps[index].reps, in: 1...20)
                                .accessibilityLabel("Warm-up set \(index + 1) repetitions")
                                .accessibilityValue("\(steps[index].reps)")
                        }
                    }.onDelete { steps.remove(atOffsets: $0) }
                    if steps.count < 8 {
                        Button("Add warm-up") {
                            steps.append(WarmupStep(percent: min(99, (steps.last?.percent ?? 30) + 5), reps: 1))
                        }
                    }
                    Button("Restore starter progression") { steps = WarmupStep.standard }
                    Button("Build loadable warm-ups") { warmups() }
                    if runner.busy { ProgressView("Planning…") }
                    if let error = runner.error { InputErrorView(message: error) }
                    Text("Starter sets are an editable example, not a universal program. Loads round down; below-bar percentages may start at the bar. Repeated loads are omitted.").font(.footnote)
                }
                if let plan = runner.value {
                    Section("\(lift) · planned session") {
                        if plan.top.total != plan.requestedTop {
                            Text("Requested top \(plan.requestedTop.formatted(in: equipment.displayUnit)) \(equipment.displayUnit.symbol) is unavailable. Using the load below it.").foregroundStyle(.orange)
                        }
                        if plan.omittedSteps > 0 { Text("\(plan.omittedSteps) progression rows omitted because they could not add a distinct warm-up load.").font(.footnote) }
                        ForEach(Array(plan.sets.enumerated()), id: \.offset) { index, set in
                            Text("Percentage target: \(set.requested.formatted(in: equipment.displayUnit)) \(equipment.displayUnit.symbol). Actual load shown below.").font(.caption).foregroundStyle(.secondary)
                            PlannedLoadView(title: "Warm-up \(index + 1) · \(set.step.reps) reps · \(set.step.percent)% requested", load: set.load, unit: equipment.displayUnit)
                        }
                        PlannedLoadView(title: "Top set · \(topReps) reps", load: plan.top, unit: equipment.displayUnit)
                    }
                }
            }.navigationTitle("Training")
                .onAppear { performed.display(in: equipment.displayUnit); top.display(in: equipment.displayUnit) }
                .onChange(of: equipment.displayUnit) { _, unit in performed.display(in: unit); top.display(in: unit) }
                .onChange(of: equipment.settingsRevision) { _, _ in runner.clear() }
                .onChange(of: steps) { _, _ in runner.clear() }
                .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { dismissKeyboard() } } }
        }
    }
    private func estimate() {
        do {
            guard let count = Int(reps), String(count) == reps.trimmingCharacters(in: .whitespaces) else { throw TrainingError.invalidReps }
            let weight = try performed.positive()
            estimates = try Dictionary(uniqueKeysWithValues: OneRepFormula.allCases.map { ($0, try $0.estimate(weight: weight, reps: count)) })
            estimateError = nil
        } catch { estimates = [:]; estimateError = error.localizedDescription }
    }
    private func warmups() {
        do {
            let target = try top.positive(), steps = steps, bar = equipment.equipment, inventory = equipment.inventory
            runner.run { try WarmupPlanner.plan(topTarget: target, steps: steps, equipment: bar, inventory: inventory) }
        } catch { runner.fail(error) }
    }
}

@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
