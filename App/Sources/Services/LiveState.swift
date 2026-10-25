import Foundation

/// Values that change many times a second (song position, output meter). Kept out of
/// `AppModel` so only the few small views that show them redraw — not the whole app.
@MainActor
final class LiveState: ObservableObject {
    @Published private(set) var position: Double?
    @Published var peak: Float = 0
    @Published var clipped = false

    /// Updates the position at most ~10× a second (and immediately when it starts or stops).
    func setPosition(_ p: Double?) {
        switch (position, p) {
        case (nil, nil): return
        case (let old?, let new?) where abs(old - new) < 0.1: return
        default: position = p
        }
    }

    func setPeak(_ value: Float, clipped c: Bool) {
        // Meter changes under 2% are invisible.
        if abs(value - peak) >= 0.02 { peak = value }
        if c, !clipped { clipped = true }
    }
}
