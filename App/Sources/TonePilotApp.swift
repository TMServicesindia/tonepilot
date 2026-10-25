import SwiftUI

@main
struct TonePilotApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .sheet(isPresented: Binding(get: { !hasCompletedSetup }, set: { if !$0 { hasCompletedSetup = true } })) {
                    SetupWizardView { hasCompletedSetup = true }
                        .environmentObject(model)
                        .interactiveDismissDisabled()
                }
                .onAppear { model.resumeInterruptedAnalyses() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack { LibraryView() }
                .tabItem { Label("Library", systemImage: "music.note.list") }.tag(AppTab.library)
            NavigationStack { AnalyseHomeView() }
                .tabItem { Label("Analyse", systemImage: "waveform.badge.magnifyingglass") }.tag(AppTab.analyse)
            StudioTab()
                .tabItem { Label("Studio", systemImage: "pianokeys") }.tag(AppTab.studio)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(AppTab.settings)
        }
        .overlay(alignment: .top) {
            if let error = model.engineError {
                Text(error).font(.footnote).padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Theme.bad.opacity(0.9))
                    .onTapGesture { model.engineError = nil }
            }
        }
    }
}
