// swift-tools-version:5.9
import PackageDescription

// Platform-independent core of TonePilot: data models, persistence,
// MIDI parsing/routing and offline audio analysis. No Apple-only
// frameworks are used here so the package builds and tests on Linux CI too.
let package = Package(
    name: "TonePilotCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TonePilotCore", targets: ["TonePilotCore"]),
        // Shared library for the Android app (JNI shim calls its C entry points).
        .library(name: "TonePilotBridge", type: .dynamic, targets: ["TonePilotBridge"])
    ],
    targets: [
        .target(name: "TonePilotCore"),
        .target(name: "TonePilotBridge", dependencies: ["TonePilotCore"]),
        .testTarget(name: "TonePilotCoreTests", dependencies: ["TonePilotCore", "TonePilotBridge"])
    ]
)
