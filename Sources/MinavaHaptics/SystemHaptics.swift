import Foundation
import MinavaCore
import MinavaPanic

/// Picks the best haptics the current device can offer.
///
/// Never returns `nil` and never throws. An exercise that cannot vibrate still runs — the
/// curve and the text carry it — and the person is not told that something failed. A person
/// mid-episode has no use for an error message.
public enum SystemHaptics {
    public static func make() -> HapticPort {
        #if os(watchOS)
        return WatchHapticPort()
        #elseif os(iOS)
        if HapticEngine.isSupported {
            return HapticEngine()
        }
        return SilentHapticPort()
        #else
        return SilentHapticPort()
        #endif
    }
}

/// Does nothing, on purpose.
///
/// Used on hardware without haptics, in the simulator, and in tests. Its existence is what
/// lets the rest of the code stop asking whether haptics are available.
public struct SilentHapticPort: HapticPort {
    public init() {}
    public func begin(
        phase: BreathingPlan.Phase.Kind,
        duration: TimeInterval,
        intensity: BreathingPlan.Phase.HapticIntensity?
    ) {}
    public func stop() {}
}

/// Records what it was asked to do, for tests.
public final class RecordingHapticPort: HapticPort, @unchecked Sendable {
    public struct Call: Equatable, Sendable {
        public let phase: BreathingPlan.Phase.Kind
        public let duration: TimeInterval
        public let intensity: BreathingPlan.Phase.HapticIntensity?
    }

    public private(set) var calls: [Call] = []
    public private(set) var stopCount = 0

    public init() {}

    public func begin(
        phase: BreathingPlan.Phase.Kind,
        duration: TimeInterval,
        intensity: BreathingPlan.Phase.HapticIntensity?
    ) {
        calls.append(Call(phase: phase, duration: duration, intensity: intensity))
    }

    public func stop() { stopCount += 1 }
}
