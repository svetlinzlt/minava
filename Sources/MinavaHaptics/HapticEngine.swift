#if os(iOS)
import CoreHaptics
import Foundation
import MinavaCore
import MinavaPanic

/// The real haptic engine on iPhone.
///
/// This is the only place in the package that imports CoreHaptics. `MinavaPanic` knows only
/// `HapticPort`, so the exercise logic stays testable on any machine and the thing that can
/// actually fail stays behind a visible boundary.
///
/// Nothing here decides how long a phase lasts. It receives a phase and a duration and makes
/// them felt.
public final class HapticEngine: HapticPort, @unchecked Sendable {
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private let fallback: HapticPort?

    /// Whether this device can play patterned haptics at all. iPad and the simulator cannot.
    public static var isSupported: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// - Parameter fallback: used when patterned haptics are unavailable. Passing `nil`
    ///   means the exercise runs silently and without vibration, which is still a complete
    ///   exercise — the curve and the text carry it.
    public init(fallback: HapticPort? = nil) {
        self.fallback = fallback
        guard HapticEngine.isSupported else { return }
        engine = try? CHHapticEngine()
        configure()
    }

    private func configure() {
        guard let engine else { return }

        // The whole point: vibration must work with the ringer switch on silent. A person in
        // a meeting or next to someone asleep is the ordinary case, not the exception.
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = false

        // The system stops the engine for its own reasons — a phone call, memory pressure,
        // the app going to the background. Both handlers exist so the exercise does not end
        // in silence without anyone noticing.
        engine.resetHandler = { [weak self] in
            try? self?.engine?.start()
            self?.player = nil
        }
        engine.stoppedHandler = { _ in }

        try? engine.start()
    }

    // MARK: - HapticPort

    public func begin(
        phase: BreathingPlan.Phase.Kind,
        duration: TimeInterval,
        intensity: BreathingPlan.Phase.HapticIntensity?
    ) {
        guard let engine else {
            fallback?.begin(phase: phase, duration: duration, intensity: intensity)
            return
        }
        do {
            let pattern = try Self.pattern(for: phase, duration: duration, intensity: intensity)
            let player = try engine.makePlayer(with: pattern)
            self.player = player
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // A failed pattern must never surface as an error to a person mid-episode.
            fallback?.begin(phase: phase, duration: duration, intensity: intensity)
        }
    }

    public func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        fallback?.stop()
    }

    // MARK: - Patterns

    /// One clear tap where the phase begins, then a continuous body for its whole length.
    ///
    /// There is deliberately no separate end marker: the end of one phase is the start of the
    /// next, and two signals at the same moment feel like a stutter.
    static func pattern(
        for phase: BreathingPlan.Phase.Kind,
        duration: TimeInterval,
        intensity: BreathingPlan.Phase.HapticIntensity?
    ) throws -> CHHapticPattern {
        let sharpness = Float(phase == .inhale ? 0.45 : 0.25)

        let onset = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.75),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0)

        let body = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
            ],
            relativeTime: 0,
            duration: duration)

        return try CHHapticPattern(
            events: [onset, body],
            parameterCurves: [envelope(for: intensity, duration: duration)])
    }

    /// Rising through an inhale, falling through an exhale, flat while holding.
    /// Which phase gets which shape is part of the protocol, not of this file.
    static func envelope(
        for intensity: BreathingPlan.Phase.HapticIntensity?,
        duration: TimeInterval
    ) -> CHHapticParameterCurve {
        let points: [CHHapticParameterCurve.ControlPoint]
        switch intensity {
        case .rising:
            points = [.init(relativeTime: 0, value: 0.2),
                      .init(relativeTime: duration, value: 1.0)]
        case .falling:
            points = [.init(relativeTime: 0, value: 1.0),
                      .init(relativeTime: duration, value: 0.2)]
        case .steady, .none:
            points = [.init(relativeTime: 0, value: 0.6),
                      .init(relativeTime: duration, value: 0.6)]
        }
        return CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: points,
            relativeTime: 0)
    }
}
#endif
