import SwiftUI

/// TonePilot Lab: measures the instrument-recognition candidate (EfficientAT Core ML) on THIS iPhone.
/// Research only. Nothing here affects the TonePilot app.
@main
struct LabApp: App {
    var body: some Scene { WindowGroup { LabView() } }
}

struct LabView: View {
    @StateObject private var bench = LabBenchmark()
    var body: some View {
        NavigationStack {
            List {
                Section("Run") {
                    Button("Quick run (~3 min, one run per song length)") { Task { await bench.run(sustainedSeconds: 60) } }
                        .disabled(bench.running).accessibilityIdentifier("lab.quick")
                    Button("Full run (~20 min, 3 runs per song length → median/p90; keep the phone unplugged)") { Task { await bench.run(sustainedSeconds: 300) } }
                        .disabled(bench.running).accessibilityIdentifier("lab.full")
                    if let url = bench.reportURL { ShareLink("Share report (JSON)", item: url).accessibilityIdentifier("lab.share") }
                }
                Section("Progress") {
                    ForEach(Array(bench.log.enumerated()), id: \.offset) { _, line in Text(line).font(.footnote.monospaced()) }
                }
            }
            .navigationTitle("TonePilot Lab")
        }
    }
}
