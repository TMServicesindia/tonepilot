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
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { LibraryView() }
                .tabItem { Label("Library", systemImage: "music.note.list") }.tag(0)
            NavigationStack { AnalyseHomeView() }
                .tabItem { Label("Analyse", systemImage: "waveform.badge.magnifyingglass") }.tag(1)
            NavigationStack { ToneStudioHomeView() }
                .tabItem { Label("Tone Studio", systemImage: "slider.vertical.3") }.tag(2)
            PerformanceView()
                .tabItem { Label("Perform", systemImage: "pianokeys") }.tag(3)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
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
