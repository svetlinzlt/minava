import Foundation
import MinavaCore

/// Drives one practice from the training mode: the rating before, the steps, the rating after.
///
/// The counterpart of `PanicSession`, and deliberately not the same type. A breathing episode
/// is driven by a clock — the exhale lasts six seconds whether or not the person is ready. A
/// practice is driven by the person: the app shows a step and waits. Time appears here only
/// as a **floor**, never as a deadline, so that nobody is moved on before they have arrived.
///
/// Like its counterpart it owns no clock and no storage. The host advances it and the host
/// decides what to do with the two ratings; this module cannot import `MinavaSync` and must
/// not learn how anything is saved.
public final class PracticeSession {

    /// Where the session is. The order is fixed and a stage is never skipped backwards.
    public enum Stage: Equatable, Sendable {
        /// Nothing has begun. The screen shows the title and one button.
        case ready
        /// Asking "колко силно е сега, от 0 до 10". Only when the protocol has a measure.
        case ratingBefore
        /// Walking the steps. `index` is into `sequence`.
        case running(index: Int)
        /// Asking the same question again, so the change can be seen.
        case ratingAfter
        /// Done. The app waits and asks nothing further.
        case finished
    }

    public enum Event: Equatable, Sendable {
        case started
        case asksRating(before: Bool)
        case step(ExecutablePractice.Step, index: Int, of: Int)
        /// The practice ended. `change` is present only when both ratings were given.
        case finished(change: Int?)
        /// An exposure practice ended and the person must be taken to its recovery practice.
        /// Not a suggestion: the identifier is carried so the app cannot forget.
        case mustRecover(protocolID: String)
        case stopped
    }

    public let practice: ExecutablePractice
    public private(set) var stage: Stage = .ready
    public private(set) var before: Int?
    public private(set) var after: Int?

    /// True while running unapproved content. The screen must say so, visibly.
    public var isProvisional: Bool { practice.isProvisional }

    private let sequence: [ExecutablePractice.Step]
    private let onEvent: (Event) -> Void
    /// When the current step appeared, in the host's own clock.
    private var stepStartedAt: TimeInterval = 0

    /// Takes an `ExecutablePractice`, never a raw file. The gate is passed before a session
    /// can exist, so there is no path here that goes around it.
    public init(practice: ExecutablePractice, onEvent: @escaping (Event) -> Void) {
        self.practice = practice
        self.sequence = practice.sequence
        self.onEvent = onEvent
    }

    public var stepCount: Int { sequence.count }

    public var currentStep: ExecutablePractice.Step? {
        guard case .running(let index) = stage, index < sequence.count else { return nil }
        return sequence[index]
    }

    /// Whether the person is asked to rate at all.
    public var asksForRating: Bool { practice.measure != nil }

    /// Begins. `now` is the host's clock reading, in seconds; any origin will do.
    public func start(now: TimeInterval = 0) {
        guard stage == .ready else { return }
        onEvent(.started)
        if asksForRating {
            stage = .ratingBefore
            onEvent(.asksRating(before: true))
        } else {
            enterRunning(at: 0, now: now)
        }
    }

    /// Records a rating for whichever question is on screen and moves on.
    ///
    /// Out of range is refused rather than clamped: a clamped 11 would silently become a 10
    /// and the number would stop meaning what the person chose.
    @discardableResult
    public func rate(_ value: Int, now: TimeInterval = 0) -> Bool {
        guard ActivationScale.range.contains(value) else { return false }

        switch stage {
        case .ratingBefore:
            before = value
            enterRunning(at: 0, now: now)
            return true
        case .ratingAfter:
            after = value
            finish()
            return true
        default:
            return false
        }
    }

    /// Whether the person may move to the next step yet.
    ///
    /// A step with a minimum duration holds the button until it has passed. Not to enforce
    /// discipline — to stop a practice from being tapped through in four seconds, which is
    /// the same as not doing it.
    public func canAdvance(now: TimeInterval) -> Bool {
        guard case .running = stage, let step = currentStep else { return false }
        guard let minimum = step.minDuration else { return true }
        return now - stepStartedAt >= minimum
    }

    /// Seconds still to wait on this step. Zero when the button is live.
    public func remainingOnStep(now: TimeInterval) -> TimeInterval {
        guard case .running = stage, let minimum = currentStep?.minDuration else { return 0 }
        return max(0, minimum - (now - stepStartedAt))
    }

    /// The person tapped "Продължи". Ignored while the minimum has not passed.
    @discardableResult
    public func advance(now: TimeInterval) -> Bool {
        guard case .running(let index) = stage, canAdvance(now: now) else { return false }

        let next = index + 1
        if next < sequence.count {
            enterRunning(at: next, now: now)
        } else if asksForRating {
            stage = .ratingAfter
            onEvent(.asksRating(before: false))
        } else {
            finish()
        }
        return true
    }

    /// Leaves in the middle. Always available: a practice nobody may leave is a trap.
    ///
    /// Nothing is recorded, not even a rating already given — half a measurement is not a
    /// measurement, and this is also the honest answer to "what if I stop": nothing happens.
    ///
    /// One thing does still happen. A challenge abandoned halfway leaves a person more
    /// raised than one carried through, not less, so the way back is demanded here too.
    public func stop() {
        guard stage != .finished else { return }
        let hadBegun = stage != .ready
        before = nil
        after = nil
        stage = .finished
        onEvent(.stopped)
        if hadBegun { demandRecoveryIfNeeded() }
    }

    /// The change between the two ratings. Negative means calmer.
    public var change: Int? {
        guard let before, let after else { return nil }
        return after - before
    }

    private func enterRunning(at index: Int, now: TimeInterval) {
        guard index < sequence.count else {
            finish()
            return
        }
        stage = .running(index: index)
        stepStartedAt = now
        onEvent(.step(sequence[index], index: index, of: sequence.count))
    }

    private func finish() {
        stage = .finished
        onEvent(.finished(change: change))
        demandRecoveryIfNeeded()
    }

    /// An exposure practice deliberately raises activation. Ending there and returning a
    /// person to their day is the thing two independent sources warn against, so the way
    /// back is an event the app has to handle, not a line of advice it may skip.
    private func demandRecoveryIfNeeded() {
        guard practice.kind == .exposure, let recovery = practice.recoveryProtocol else {
            return
        }
        onEvent(.mustRecover(protocolID: recovery))
    }
}

/// The 0–10 scale, in one place.
///
/// The bounds live here as well as in `MinavaSync.ActivationReading` because the two are
/// asked at different moments — the screen must refuse an impossible number before anything
/// is stored, and storage must refuse it again without trusting the screen.
public enum ActivationScale {
    public static let range = 0...10
}
