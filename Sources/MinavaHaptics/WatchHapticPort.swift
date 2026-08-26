#if os(watchOS)
import Foundation
import MinavaCore
import MinavaPanic
import WatchKit

/// Haptics on the wrist.
///
/// The watch does not offer the same control as the phone. `WKInterfaceDevice` plays named
/// haptics of fixed length; there is no envelope and no continuous body that can rise through
/// an inhale. So the watch marks the *boundaries* of phases rather than their shape.
///
/// That is not a downgrade of the exercise. The watch is pressed against the skin, and a
/// clear tap at each change is enough to breathe by without looking.
///
/// Whether CoreHaptics offers finer control on current watchOS is an open question for the
/// device session described in docs/ХАПТИКА.md. If it does, this type gains a second
/// implementation and nothing else in the package changes.
public final class WatchHapticPort: HapticPort, @unchecked Sendable {
    private var repeater: Timer?

    public init() {}

    public func begin(
        phase: BreathingPlan.Phase.Kind,
        duration: TimeInterval,
        intensity: BreathingPlan.Phase.HapticIntensity?
    ) {
        stop()
        WKInterfaceDevice.current().play(Self.haptic(for: phase))

        // Holds are the phases where a person is most likely to lose the thread, so they get
        // a quiet reminder halfway through. Inhale and exhale are carried by their edges.
        guard phase == .holdIn || phase == .holdOut, duration >= 4 else { return }
        repeater = Timer.scheduledTimer(withTimeInterval: duration / 2, repeats: false) { _ in
            WKInterfaceDevice.current().play(.click)
        }
    }

    public func stop() {
        repeater?.invalidate()
        repeater = nil
    }

    static func haptic(for phase: BreathingPlan.Phase.Kind) -> WKHapticType {
        switch phase {
        case .inhale: return .directionUp
        case .exhale: return .directionDown
        case .holdIn, .holdOut: return .click
        }
    }
}
#endif
