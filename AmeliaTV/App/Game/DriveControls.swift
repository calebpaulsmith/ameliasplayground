import Foundation

/// Shared, lightweight input state the scene reads every frame. The on-screen
/// touch buttons (iPhone/iPad) write to it; the scene also polls GameController
/// (Siri Remote + MFi) directly. Keeping one state means every input device
/// drives the bus the same way.
final class DriveControls {
    /// -1 (full left) … +1 (full right).
    var steer: Double = 0
    /// Held to slow/stop. The bus otherwise auto-rolls forward (kid-friendly:
    /// you steer and honk; you never have to manage a throttle).
    var braking: Bool = false
    /// True once a human has touched any control — the demo attract-drive then
    /// hands the wheel over for good.
    var engaged: Bool = false

    private var honkPending = false

    func setSteer(_ s: Double) { steer = s; if s != 0 { engaged = true } }
    func setBraking(_ b: Bool) { braking = b; if b { engaged = true } }
    func requestHonk() { honkPending = true; engaged = true }

    /// One-shot read of a honk request.
    func consumeHonk() -> Bool {
        defer { honkPending = false }
        return honkPending
    }
}
