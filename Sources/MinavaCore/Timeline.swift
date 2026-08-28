import Foundation

/// One timed step of an exercise.
public struct TimelineStep: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case entry
        case phase(BreathingPlan.Phase.Kind)
        case exit
    }

    public let kind: Kind
    /// Seconds from the start of the exercise.
    public let start: TimeInterval
    public let duration: TimeInterval
    /// Zero-based cycle this step belongs to; `nil` for entry and exit.
    public let cycle: Int?
    public let hapticIntensity: BreathingPlan.Phase.HapticIntensity?
    /// Carried through so the interface can say how full the breath is, not only how long.
    public let depth: BreathingPlan.Phase.Depth?

    public var end: TimeInterval { start + duration }

    public init(
        kind: Kind,
        start: TimeInterval,
        duration: TimeInterval,
        cycle: Int?,
        hapticIntensity: BreathingPlan.Phase.HapticIntensity?,
        depth: BreathingPlan.Phase.Depth? = nil
    ) {
        self.kind = kind
        self.start = start
        self.duration = duration
        self.cycle = cycle
        self.hapticIntensity = hapticIntensity
        self.depth = depth
    }
}

/// Turns a plan into a flat list of timed steps.
///
/// The engine is deterministic on purpose. The same plan yields the same seconds every
/// time — no randomness, no variation "for variety". Without that it cannot be tested, and
/// we cannot say afterwards what a person actually received.
public enum Timeline {
    public static func steps(
        for plan: BreathingPlan,
        tempo: Double = 1
    ) -> [TimelineStep] {
        let tempo = clampedTempo(tempo, plan: plan)
        var steps: [TimelineStep] = []
        var clock: TimeInterval = 0

        if plan.entry.duration > 0 {
            steps.append(TimelineStep(kind: .entry,
                                      start: clock,
                                      duration: plan.entry.duration,
                                      cycle: nil,
                                      hapticIntensity: nil))
            clock += plan.entry.duration
        }

        let firstFactor = plan.repeat.firstCycleFactor ?? 1
        for index in 0..<plan.repeat.cycles {
            let factor = (index == 0 ? firstFactor : 1) * tempo
            for phase in plan.cycle.phases {
                let duration = phase.duration * factor
                steps.append(TimelineStep(kind: .phase(phase.type),
                                          start: clock,
                                          duration: duration,
                                          cycle: index,
                                          hapticIntensity: phase.hapticIntensity,
                                          depth: phase.depth))
                clock += duration
            }
        }

        steps.append(TimelineStep(kind: .exit,
                                  start: clock,
                                  duration: plan.exit.duration,
                                  cycle: nil,
                                  hapticIntensity: nil))
        return steps
    }

    /// A person may slow the exercise down only within the range the protocol allows.
    /// A protocol without `userTempo` forbids it entirely.
    public static func clampedTempo(_ tempo: Double, plan: BreathingPlan) -> Double {
        guard let range = plan.userTempo else { return 1 }
        return Swift.min(Swift.max(tempo, range.min), range.max)
    }

    /// The step covering a given moment, or `nil` once the exercise is over.
    public static func step(at time: TimeInterval, in steps: [TimelineStep]) -> TimelineStep? {
        steps.first { time >= $0.start && time < $0.end }
    }
}
