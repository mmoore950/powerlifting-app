import SwiftUI
import LiftingCore

@MainActor
struct ToolkitView: View {
    @StateObject private var equipment = LoadingModel()
    var body: some View {
        TabView {
            PlateLoadingView(model: equipment).tabItem { Label("Plates", systemImage: "scalemass") }
            TrainingView(equipment: equipment).tabItem { Label("Training", systemImage: "figure.strengthtraining.traditional") }
            AttemptsView(equipment: equipment).tabItem { Label("Attempts", systemImage: "list.number") }
            OPLBrowserView().tabItem { Label("Competition", systemImage: "person.3") }
            VideoAnalysisView().tabItem { Label("Bar path", systemImage: "video") }
        }.tint(.mint).preferredColorScheme(.dark)
    }
}
