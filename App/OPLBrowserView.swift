import SwiftUI
import LiftingCore

@MainActor
struct OPLBrowserView: View {
    @StateObject private var model = OPLBrowserModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var configuration = false
    @State private var mode = "Lifters"
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OPLFreshnessView(model: model)
                if model.repository != nil {
                    Picker("Browse", selection: $mode) {
                        Text("Lifters").tag("Lifters")
                        Text("Best performances").tag("Best performances")
                    }.pickerStyle(.segmented).padding()
                    if mode == "Lifters" { OPLSearchView(model: model) }
                    else { OPLRankingsView(model: model) }
                } else {
                    ContentUnavailableView {
                        Label("Competition data not connected", systemImage: "person.text.rectangle")
                    } description: {
                        Text("Competition search needs a configured data connection. Open Settings to check availability. Previously saved results appear when that connection's cache is available.")
                    } actions: {
                        Button("Open data settings") { configuration = true }
                    }
                }
            }
            .navigationTitle("Competition data")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(model.repository == nil || model.refreshing).accessibilityLabel("Refresh dataset and results")
                    Button { configuration = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Competition data settings")
                }
            }
            .sheet(isPresented: $configuration) { OPLServiceSettings(model: model) }
            .task { await model.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refresh() } }
            }
        }
    }
}

@MainActor
struct OPLFreshnessView: View {
    @ObservedObject var model: OPLBrowserModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let metadata = model.metadata {
                Text("Source dataset: \(metadata.value.sourceDate ?? "unknown")").font(.subheadline.bold())
                Text("Service last successful check: \(metadata.value.status.lastSuccessfulCheckAt ?? "unknown")")
                Text("Saved on this device: \(metadata.savedAt.formatted(date: .abbreviated, time: .shortened))")
                if metadata.offline { Text("Live refresh unavailable — saved dataset metadata").foregroundStyle(.orange) }
                if metadata.value.sourceIsStale() { Text("Source dataset is older than two days or undated.").foregroundStyle(.orange) }
                if metadata.value.checkIsStale() { Text("Service check is stale or unknown.").foregroundStyle(.orange) }
                if let notice = metadata.notice { Text(notice).foregroundStyle(.orange) }
                Text("Data: OpenPowerlifting · public domain").foregroundStyle(.secondary)
            }
            if model.refreshing { ProgressView("Checking dataset") }
            if model.repository != nil, model.metadata == nil, !model.refreshing, model.error == nil {
                Text("Competition data is unavailable. Refresh or check the connection in Settings.")
            }
            if let error = model.error { InputErrorView(message: error) }
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
    }
}

@MainActor
private struct OPLServiceSettings: View {
    @ObservedObject var model: OPLBrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = ""
    @State private var applying = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Connection status") {
                    Text(model.repository == nil ? "No competition data connection configured." : model.metadata == nil ? "Connection configured; dataset unavailable." : "Dataset available; check source and saved dates below.")
                    OPLFreshnessView(model: model)
                }
                Section {
                    DisclosureGroup("Developer connection and diagnostics") {
                        TextField("HTTPS data service URL", text: $endpoint)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel("Developer HTTPS data service URL")
                        Text("A reachable HTTPS service must implement the documented dataset, lifter and rankings API. This app does not open the OpenPowerlifting website.")
                        Text("The local prototype runs on Windows loopback. An iPhone cannot reach that address; authorized hosting or a development connection is required.")
                        Button(applying ? "Connecting…" : "Save and connect") {
                            applying = true
                            Task {
                                await model.connect(endpoint)
                                applying = false
                                if model.error == nil { dismiss() }
                            }
                        }.disabled(applying || endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if !model.endpoint.isEmpty { Text("Configured endpoint: \(model.endpoint)").textSelection(.enabled) }
                        if let version = model.version { Text("Dataset version: \(version)").textSelection(.enabled) }
                        else { Text("No dataset version available.") }
                    }
                }
            }.navigationTitle("Competition settings")
                .toolbar { Button("Close") { dismiss() } }
                .onAppear { endpoint = model.endpoint }
        }
    }
}

@MainActor
private struct OPLSearchView: View {
    @ObservedObject var model: OPLBrowserModel
    @StateObject private var page = OPLPageStore<OPLLifter>()
    @State private var text = ""
    private var query: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        List {
            Section {
                TextField("Lifter name prefix (at least 2 characters)", text: $text)
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                    .accessibilityLabel("Search lifters by name, 2 to 128 characters")
                Text("Source suffixes such as #1 identify separate source names.").font(.caption).foregroundStyle(.secondary)
                if !query.isEmpty, query.count < 2 { Text("Enter at least two characters to search.").font(.caption) }
                if query.count > 128 { InputErrorView(message: "Use a name prefix of 2 to 128 characters.") }
            }
            OPLPageStatus(page: page)
            ForEach(page.items) { lifter in
                NavigationLink(lifter.name) { OPLHistoryView(model: model, lifter: lifter) }
            }
            if query.count >= 2, page.loadedVersion != nil, !page.loading, page.error == nil, page.items.isEmpty {
                Text("No matching source names.").foregroundStyle(.secondary)
            }
            OPLMoreButton(page: page)
        }.task(id: "\(model.revision):\(query)") {
            guard (2...128).contains(query.count) else {
                await page.reset(client: nil, version: nil, query: nil); return
            }
            await page.reset(client: model.repository, version: model.version,
                query: OPLQuery(path: "lifters", parameters: ["q": query]),
                adoptDataset: model.adoptRecovery, delayNanoseconds: 400_000_000)
        }.refreshable { await model.refresh() }
    }
}

@MainActor
private struct OPLHistoryView: View {
    @ObservedObject var model: OPLBrowserModel
    let lifter: OPLLifter
    @StateObject private var page = OPLPageStore<OPLResult>()
    @StateObject private var summary = OPLPageStore<OPLProfileSummary>()
    @State private var scope: [String: String]
    @State private var additionalDraft: [String: String]
    @FocusState private var focusedAdditional: String?
    init(model: OPLBrowserModel, lifter: OPLLifter, filters: [String: String] = [:]) {
        self.model = model; self.lifter = lifter
        let initial = OPLProfileScope.parameters(from: filters)
        _scope = State(initialValue: initial)
        _additionalDraft = State(initialValue: OPLProfileScope.additionalDraft(from: initial))
    }
    private struct ProfileTaskID: Equatable {
        let revision: Int
        let scope: [String: String]
    }
    private var summaryTask: ProfileTaskID { ProfileTaskID(revision: model.revision, scope: scope) }
    private var consistentVersion: Bool {
        model.version != nil && summary.loadedVersion == model.version && page.loadedVersion == model.version
    }
    var body: some View {
        List {
            Section {
                Text(lifter.name).font(.headline).lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                OPLFreshnessView(model: model)
                Text("Exact source name; suffixes are preserved. Source names do not establish identity across renamed entries.").font(.caption)
            }
            Section("Profile best performances") {
                profilePicker("Source sex category", key: "sex", choices: ["M", "F", "Mx"])
                profilePicker("Equipment", key: "equipment", choices: ["Raw", "Wraps", "Single-ply", "Multi-ply", "Unlimited", "Straps"])
                profilePicker("Event", key: "event", choices: ["SBD", "BD", "SD", "SB", "S", "B", "D"])
                Picker("Tested designation", selection: Binding(get: { scope["tested"] ?? "" }, set: { scope["tested"] = $0.isEmpty ? nil : $0 })) {
                    Text("Any designation").tag("")
                    Text("Yes").tag("yes")
                    Text("Not designated").tag("not-designated")
                }
                DisclosureGroup("More profile filters") {
                    OPLAdditionalFilterEditor(draft: $additionalDraft, focus: $focusedAdditional)
                    if additionalDraft != OPLProfileScope.additionalDraft(from: scope) {
                        Text("Edits have not been applied. Best values below still use the applied filters.").font(.caption)
                    }
                    Button("Apply profile filters") {
                        focusedAdditional = nil
                        scope = OPLProfileScope.applyingAdditional(additionalDraft, to: scope)
                        additionalDraft = OPLProfileScope.additionalDraft(from: scope)
                    }.accessibilityHint("Applies the six optional filters to profile best performances. Meet history stays independent.")
                }
                Text("Applied profile filters").font(.caption.bold()).accessibilityAddTraits(.isHeader)
                ForEach(scope.keys.sorted(), id: \.self) { key in Text(scopeLabel(key)).font(.caption).lineLimit(nil).fixedSize(horizontal: false, vertical: true) }
                if !additionalDraft.isEmpty || !OPLProfileScope.additionalDraft(from: scope).isEmpty {
                    Button("Clear additional filters") {
                        focusedAdditional = nil
                        scope = OPLProfileScope.applyingAdditional([:], to: scope)
                        additionalDraft = [:]
                    }
                        .accessibilityHint("Discards optional draft edits and clears applied optional filters. Keeps the selected sex category, equipment, event and tested designation.")
                }
                Text("Best eligible values across this entire dataset for these filters; not ratified records. Lift bests can come from different meets and do not add up to a competition total.").font(.caption)
                OPLPageStatus(page: summary, retryLabel: "Retry profile",
                    retryHint: "Retries the applied profile filters. Draft edits require Apply profile filters.",
                    beforeRetry: { focusedAdditional = nil })
                if consistentVersion, let profile = summary.items.first, profile.scope == scope {
                    ForEach(["total", "squat", "bench", "deadlift", "dots"], id: \.self) { metric in
                        if let best = profile.bests.first(where: { $0.metric == metric }), let value = best.value {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(metric == "dots" ? "DOTS" : metric.capitalized): \(value.formatted(.number.precision(.fractionLength(0...2))))\(metric == "dots" ? "" : " kg")").font(.headline).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                Text("\(best.result.meet) · \(best.result.date) · \(best.result.federation)").font(.caption).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                            }.accessibilityElement(children: .combine)
                                .accessibilityLabel(bestAccessibilityLabel(best, value: value))
                        } else { Text("\(metric == "dots" ? "DOTS" : metric.capitalized): no eligible value for these filters").font(.caption) }
                    }
                } else if consistentVersion, summary.items.isEmpty, !summary.loading, summary.error == nil {
                    Text("This source name is absent from the selected dataset.")
                }
                if let previous = summary.items.first, previous.scope != scope {
                    Text("Profile filters changed. Previous best values are hidden while results update.").font(.caption)
                }
                if !consistentVersion, !summary.items.isEmpty || !page.items.isEmpty {
                    Text("Profile and history are updating to the same dataset. Previous values are hidden.").font(.caption)
                }
            }
            Section("Meet history · all categories") {
                Text("All rows for this exact source name, independent of profile filters. Divisions can produce repeated meet rows.").font(.caption)
                OPLPageStatus(page: page, retryLabel: "Retry meet history",
                    retryHint: "Retries all-category meet history for this source name.", beforeRetry: { focusedAdditional = nil })
                if page.loadedVersion == model.version {
                    ForEach(page.items) { result in OPLResultRow(result: result) }
                    if !page.loading, page.error == nil, model.version != nil, page.items.isEmpty {
                        Text("No results for this source name in the selected dataset.")
                    }
                    OPLMoreButton(page: page)
                }
            }
        }.scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedAdditional != nil {
                        Spacer()
                        Button("Done") { focusedAdditional = nil }
                            .accessibilityHint("Dismisses the keyboard without applying draft filters.")
                    }
                }
            }
            .navigationTitle(lifter.name).navigationBarTitleDisplayMode(.inline)
            .task(id: model.revision) {
                await page.reset(client: model.repository, version: model.version,
                    query: OPLQuery(path: "lifters/\(lifter.lifterID)/results"), adoptDataset: model.adoptRecovery)
            }
            .task(id: summaryTask) {
                await summary.reset(client: model.repository, version: model.version,
                    query: OPLQuery(path: "lifters/\(lifter.lifterID)/summary", parameters: scope), adoptDataset: model.adoptRecovery)
            }.refreshable { await model.refresh() }
    }
    private func bestAccessibilityLabel(_ best: OPLProfileSummary.Best, value: Double) -> String {
        let metric = best.metric == "dots" ? "DOTS score" : best.metric
        let amount = value.formatted(.number.precision(.fractionLength(0...2)))
        let unit = best.metric == "dots" ? "" : " kilograms"
        return "Best \(metric), \(amount)\(unit), \(best.result.meet), \(best.result.date), \(best.result.federation)"
    }
    private func scopeLabel(_ key: String) -> String {
        let labels = ["sex": "Source sex category", "equipment": "Equipment", "event": "Event",
            "tested": "Tested designation", "federation": "Federation", "from": "From date", "to": "Through date",
            "bodyweightMin": "Minimum bodyweight (kg)", "bodyweightMax": "Maximum bodyweight (kg)", "weightClass": "Exact source weight class"]
        let value = scope[key] ?? ""
        return "\(labels[key] ?? key): \(key == "tested" && value == "not-designated" ? "not designated" : value)"
    }
    private func profilePicker(_ title: String, key: String, choices: [String]) -> some View {
        Picker(title, selection: Binding(get: { scope[key] ?? choices[0] }, set: { scope[key] = $0 })) {
            ForEach(choices, id: \.self) { Text($0).tag($0) }
        }
    }
}

@MainActor
private struct OPLRankingsView: View {
    @ObservedObject var model: OPLBrowserModel
    @StateObject private var page = OPLPageStore<OPLResult>()
    @State private var sex = "M"
    @State private var equipment = "Raw"
    @State private var event = "SBD"
    @State private var tested = ""
    @State private var metric = "total"
    @State private var additionalDraft: [String: String] = [:]
    @FocusState private var focusedAdditional: String?
    @State private var displayedFilters: [String: String]?
    @State private var applied = ["sex": "M", "equipment": "Raw", "event": "SBD", "metric": "total"]
    @State private var filterRevision = 0
    var body: some View {
        List {
            DisclosureGroup("Filters") {
                option("Source sex category", value: $sex, choices: ["M", "F", "Mx"])
                option("Equipment", value: $equipment, choices: ["Raw", "Wraps", "Single-ply", "Multi-ply", "Unlimited", "Straps"])
                option("Event", value: $event, choices: ["SBD", "BD", "SD", "SB", "S", "B", "D"])
                Picker("Tested designation", selection: $tested) {
                    Text("Any designation").tag("")
                    Text("Yes").tag("yes")
                    Text("Not designated").tag("not-designated")
                }
                option("Performance metric", value: $metric, choices: ["total", "squat", "bench", "deadlift", "dots"])
                OPLAdditionalFilterEditor(draft: $additionalDraft, focus: $focusedAdditional)
                Button("Apply filters") { apply() }
                    .accessibilityHint("Applies the selected categories, metric and optional draft filters to rankings.")
            }.textInputAutocapitalization(.never).autocorrectionDisabled()
            Section {
                Text("Best \(applied["metric"] ?? "total") per exact source name; not federation-ratified records.").font(.caption)
                Text("\(applied["sex"] ?? "") · \(applied["equipment"] ?? "") · \(applied["event"] ?? "")").font(.caption.bold())
            }
            OPLPageStatus(page: page, retryLabel: "Retry rankings",
                retryHint: "Retries the applied ranking filters. Draft edits require Apply filters.", beforeRetry: { focusedAdditional = nil })
            if displayedFilters == applied, page.loadedVersion == model.version {
                ForEach(Array(page.items.enumerated()), id: \.element.id) { index, result in
                    NavigationLink {
                        OPLHistoryView(model: model, lifter: OPLLifter(name: result.name, lifterID: result.lifterID), filters: applied)
                    } label: {
                        VStack(alignment: .leading) {
                            Text("\(index + 1). \(result.name)").font(.headline)
                            OPLResultRow(result: result)
                        }
                    }
                }
                if !page.loading, page.error == nil, model.version != nil, page.items.isEmpty {
                    Text("No eligible performances for these filters.")
                }
                OPLMoreButton(page: page)
            } else { Text("Rankings are updating. Previous rows are hidden.").font(.caption) }
        }.scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedAdditional != nil {
                        Spacer()
                        Button("Done") { focusedAdditional = nil }
                            .accessibilityHint("Dismisses the keyboard without applying draft filters.")
                    }
                }
            }
            .task(id: "\(model.revision):\(filterRevision)") {
                let requestedFilters = applied
                await page.reset(client: model.repository, version: model.version,
                    query: OPLQuery(path: "rankings", parameters: requestedFilters), adoptDataset: model.adoptRecovery)
                if !Task.isCancelled { displayedFilters = requestedFilters }
            }.refreshable { await model.refresh() }
    }
    private func option(_ title: String, value: Binding<String>, choices: [String]) -> some View {
        Picker(title, selection: value) { ForEach(choices, id: \.self) { Text($0).tag($0) } }
    }
    private func apply() {
        focusedAdditional = nil
        var values = OPLProfileScope.applyingAdditional(additionalDraft,
            to: ["sex": sex, "equipment": equipment, "event": event, "metric": metric])
        if !tested.isEmpty { values["tested"] = tested }
        applied = values
        additionalDraft = OPLProfileScope.additionalDraft(from: values)
        filterRevision += 1
    }
}

private struct OPLAdditionalFilterEditor: View {
    @Binding var draft: [String: String]
    let focus: FocusState<String?>.Binding
    private struct Field {
        let key: String, title: String, label: String
        var decimal = false
    }
    private static let fields = [
        Field(key: "federation", title: "Exact federation (optional)", label: "Exact federation, optional"),
        Field(key: "from", title: "From YYYY-MM-DD (optional)", label: "Start date, year month day, optional"),
        Field(key: "to", title: "Through YYYY-MM-DD (optional)", label: "End date, year month day, optional"),
        Field(key: "bodyweightMin", title: "Bodyweight min kg (optional)", label: "Minimum bodyweight in kilograms, optional", decimal: true),
        Field(key: "bodyweightMax", title: "Bodyweight max kg (optional)", label: "Maximum bodyweight in kilograms, optional", decimal: true),
        Field(key: "weightClass", title: "Exact source class, e.g. 74 or 120+", label: "Exact source weight class label, optional")
    ]
    var body: some View {
        ForEach(Self.fields, id: \.key) { field in
            TextField(field.title, text: Binding(get: { draft[field.key] ?? "" }, set: { draft[field.key] = $0 }))
                .focused(focus, equals: field.key)
                .submitLabel(.done).onSubmit { focus.wrappedValue = nil }
                .keyboardType(field.decimal ? .decimalPad : .default)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel(field.label)
                .accessibilityHint("Draft filter. Use Apply to update results.")
        }
        Text("Class labels are literal upstream values, not universal federation classes. Dates are inclusive. Bodyweight filters use recorded kilograms. Best performances exclude DQ/DD/NS and unsanctioned results; eligible guest performances remain included.")
            .font(.caption).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
    }
}

private struct OPLResultRow: View {
    let result: OPLResult
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.meet).font(.subheadline.bold())
            Text("\(result.date) · \(result.federation) · \(result.equipment) · \(result.event)")
            Text("Total \(kg(result.total)) · S \(kg(result.squat)) · B \(kg(result.bench)) · D \(kg(result.deadlift))")
                .accessibilityLabel("Total \(kg(result.total)), squat \(kg(result.squat)), bench \(kg(result.bench)), deadlift \(kg(result.deadlift))")
            Text("Bodyweight \(kg(result.bodyweight)) · Class \(result.weightClass.isEmpty ? "missing" : result.weightClass)")
            Text("\(result.sex) · Division \(result.division.isEmpty ? "missing" : result.division) · Place \(result.place) · Tested \(result.tested.isEmpty ? "not designated" : result.tested)")
            if let dots = result.dots { Text("DOTS \(dots.formatted(.number.precision(.fractionLength(0...2))))") }
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func kg(_ value: Double?) -> String {
        guard let value else { return "missing" }
        return value.formatted(.number.precision(.fractionLength(0...2))) + " kg" + (value < 0 ? " (failed)" : "")
    }
}

@MainActor
private struct OPLPageStatus<Item: Codable & Identifiable & Sendable>: View {
    @ObservedObject var page: OPLPageStore<Item>
    var retryLabel = "Try again"
    var retryHint = "Retries this request."
    var beforeRetry: () -> Void = {}
    var body: some View {
        if page.loading { ProgressView("Loading results") }
        if let error = page.error {
            InputErrorView(message: error)
            Button(retryLabel) { beforeRetry(); Task { await page.retry() } }
                .disabled(page.loading).accessibilityHint(retryHint)
        }
        if page.offline { Text("Live refresh unavailable — previously saved pages").foregroundStyle(.orange) }
        if let notice = page.notice { Text(notice).font(.caption).foregroundStyle(.orange) }
        if page.loadedVersion != nil, !page.items.isEmpty {
            Text("Results saved on this device: \(page.savedAt?.formatted(date: .abbreviated, time: .shortened) ?? "unknown")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor
private struct OPLMoreButton<Item: Codable & Identifiable & Sendable>: View {
    @ObservedObject var page: OPLPageStore<Item>
    var body: some View {
        if page.cursor != nil {
            Button("Load more") { Task { await page.more() } }.disabled(page.loading)
        }
    }
}
