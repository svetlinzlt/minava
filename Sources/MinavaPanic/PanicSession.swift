import Foundation
import MinavaCore

/// What the app must be able to do for a session to run.
///
/// The session never touches Core Haptics, AVFoundation or any view. It says what should
/// happen; the app layer decides how. That keeps this module testable on any machine and
/// keeps the panic path free of anything that can fail.
public protocol HapticPort: Sendable {
    func begin(phase: BreathingPlan.Phase.Kind,
               duration: TimeInterval,
               intensity: BreathingPlan.Phase.HapticIntensity?)
    func stop()
}

public protocol VoicePort: Sendable {
    var isEnabled: Bool { get }
    func speak(_ text: String)
    func stop()
}

/// Everything the outside world may learn about a running session.
public enum SessionEvent: Equatable, Sendable {
    case started
    case step(TimelineStep)
    /// The exercise finished and the app is waiting. It asks nothing and offers nothing
    /// until the person acts.
    case finishedWaiting
    /// The person asked for the crisis screen. No confirmation, no "are you sure".
    case handedOverToHelp
    case stopped
}

/// Drives one exercise from the first breath to the pause afterwards.
///
/// Deliberately has no clock of its own: the host advances it. A session that owned a timer
/// would be untestable and would behave differently on a locked screen.
public final class PanicSession {
    public private(set) var steps: [TimelineStep]
    public private(set) var currentIndex: Int?
    public private(set) var isFinished: Bool = false

    /// Which protocol and which version produced these seconds. Worth carrying so that a
    /// question later — what exactly did this person receive — has an answer.
    public let protocolID: String
    public let protocolVersion: Int

    /// The exercise is running unapproved values in a development build. The interface must
    /// mark it unmistakably; a release build cannot reach this state at all.
    public var isProvisional: Bool

    private let haptics: HapticPort
    private let voice: VoicePort?
    private let onEvent: (SessionEvent) -> Void

    /// Takes an `ExecutablePlan`, never a raw one. The gate is passed before a session can
    /// exist, so there is no path here that skips it.
    public init(
        plan: ExecutablePlan,
        tempo: Double = 1,
        haptics: HapticPort,
        voice: VoicePort? = nil,
        onEvent: @escaping (SessionEvent) -> Void
    ) {
        self.steps = plan.timeline(tempo: tempo)
        self.protocolID = plan.protocolID
        self.protocolVersion = plan.version
        self.isProvisional = plan.isProvisional
        self.haptics = haptics
        self.voice = voice
        self.onEvent = onEvent
    }

    public var duration: TimeInterval { steps.last?.end ?? 0 }

    public func start() {
        guard !steps.isEmpty else { return }
        onEvent(.started)
        advance(to: 0)
    }

    /// Called by the host with seconds elapsed since `start()`.
    public func update(elapsed: TimeInterval) {
        guard !isFinished else { return }
        guard let index = steps.firstIndex(where: { elapsed >= $0.start && elapsed < $0.end }) else {
            finish()
            return
        }
        if index != currentIndex { advance(to: index) }
    }

    /// Leaves immediately. Nothing is asked and nothing is confirmed.
    public func handOverToHelp() {
        haptics.stop()
        voice?.stop()
        isFinished = true
        onEvent(.handedOverToHelp)
    }

    public func stop() {
        haptics.stop()
        voice?.stop()
        isFinished = true
        onEvent(.stopped)
    }

    private func advance(to index: Int) {
        currentIndex = index
        let step = steps[index]
        if case .phase(let kind) = step.kind {
            haptics.begin(phase: kind, duration: step.duration, intensity: step.hapticIntensity)
        }
        onEvent(.step(step))
    }

    private func finish() {
        haptics.stop()
        voice?.stop()
        isFinished = true
        currentIndex = nil
        // The exercise ends and the app waits. It has no opinion about how long
        // the person needs.
        onEvent(.finishedWaiting)
    }
}
