import Foundation
import GameController
import AmeliaCore

/// Adapts the GameController framework (Siri Remote + MFi/PS/Xbox) into the
/// device-agnostic `InputIntents` the Game Core consumes. This is the input
/// boundary from docs/tvos/TECHNICAL_ARCHITECTURE.md ("Input model"): the Core
/// never sees hardware.
@MainActor
final class GameControllerInput: ObservableObject {
    /// The kind of the most recently active controller (drives default assist).
    @Published private(set) var activeDevice: InputDeviceKind = .siriRemote

    // Edge-trigger latches: set when a button goes down, consumed by the Core.
    private var pendingHonk = false
    private var pendingConfirm = false
    private var pendingBack = false

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerConnected),
            name: .GCControllerDidConnect, object: nil)
        for controller in GCController.controllers() { hook(controller) }
    }

    @objc private func controllerConnected(_ note: Notification) {
        if let controller = note.object as? GCController { hook(controller) }
    }

    private func hook(_ controller: GCController) {
        activeDevice = (controller.extendedGamepad != nil) ? .controller : .siriRemote

        if let pad = controller.extendedGamepad {
            pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.pendingConfirm = true }
            }
            pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.pendingBack = true }
            }
            pad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.pendingHonk = true }
            }
        } else if let micro = controller.microGamepad {
            micro.reportsAbsoluteDpadValues = true
            micro.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.pendingConfirm = true }
            }
            micro.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.pendingHonk = true }
            }
        }
    }

    /// Polls the current hardware state and returns intents for this frame.
    /// Edge-triggered flags are consumed (reset) on read.
    func currentIntents() -> InputIntents {
        var steer = 0.0
        var throttle = 0.0
        var brake = 0.0
        var discrete = InputIntents.DiscreteTurn.none

        if let controller = GCController.controllers().first {
            if let pad = controller.extendedGamepad {
                steer = Double(pad.leftThumbstick.xAxis.value)
                if abs(steer) < 0.15 { steer = 0 }
                throttle = Double(pad.rightTrigger.value)
                if pad.buttonA.isPressed { throttle = max(throttle, 1) }
                brake = Double(pad.leftTrigger.value)
                if pad.buttonB.isPressed { brake = max(brake, 1) }
                if pad.dpad.left.isPressed { discrete = .left; steer = -1 }
                if pad.dpad.right.isPressed { discrete = .right; steer = 1 }
            } else if let micro = controller.microGamepad {
                let x = Double(micro.dpad.xAxis.value)
                if abs(x) > 0.4 {
                    steer = x
                    discrete = x < 0 ? .left : .right
                }
                let y = Double(micro.dpad.yAxis.value)
                if y > 0.4 { throttle = 1 }       // swipe/press up = go
                if y < -0.4 { brake = 1 }          // swipe/press down = stop
                if micro.buttonA.isPressed { throttle = max(throttle, 1) }
            }
        }

        let intents = InputIntents(
            steer: steer,
            throttle: throttle,
            brake: brake,
            discreteTurn: discrete,
            honkPressed: pendingHonk,
            confirmPressed: pendingConfirm,
            backPressed: pendingBack
        )
        pendingHonk = false
        pendingConfirm = false
        pendingBack = false
        return intents
    }
}
