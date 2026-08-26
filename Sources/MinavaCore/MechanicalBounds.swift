import Foundation

/// Limits of the engine, not clinical advice.
///
/// These bounds do not claim that a four second inhale is right or that a thirty second one
/// is wrong. They catch a dropped decimal point, seconds written as milliseconds, and a file
/// edited by hand. Clinical judgement lives in `clinical/`, signed and versioned.
///
/// The same numbers exist in `clinical/schema/protocol.schema.json`, which is the contract.
/// Task 3.7 adds a test that reads the schema and fails if the two ever disagree.
public enum MechanicalBounds {
    public static let phaseDuration: ClosedRange<TimeInterval> = 0.5...30
    public static let entryDuration: ClosedRange<TimeInterval> = 0...5
    public static let exitDuration: ClosedRange<TimeInterval> = 1...15
    public static let cycles: ClosedRange<Int> = 1...60
    public static let phasesPerCycle: ClosedRange<Int> = 2...4
    public static let firstCycleFactor: ClosedRange<Double> = 1...2
    public static let totalDuration: TimeInterval = 20 * 60
}

public enum ProtocolDefect: Error, Equatable, Sendable {
    case missingInhale
    case missingExhale
    case repeatedPhase(BreathingPlan.Phase.Kind)
    case phasesOutOfOrder
    case phaseCountOutOfBounds(Int)
    case durationOutOfBounds(BreathingPlan.Phase.Kind, TimeInterval)
    case entryOutOfBounds(TimeInterval)
    case exitOutOfBounds(TimeInterval)
    case cyclesOutOfBounds(Int)
    case firstCycleFactorOutOfBounds(Double)
    case tempoRangeExcludesNormal
    case totalTooLong(TimeInterval)
}

extension BreathingPlan {
    /// Throws on the first defect found. A plan that survives this is executable by the
    /// engine — which is a different and much weaker claim than being clinically sound.
    public func checkMechanicalBounds() throws {
        let kinds = cycle.phases.map(\.type)

        guard MechanicalBounds.phasesPerCycle.contains(kinds.count) else {
            throw ProtocolDefect.phaseCountOutOfBounds(kinds.count)
        }
        guard kinds.contains(.inhale) else { throw ProtocolDefect.missingInhale }
        guard kinds.contains(.exhale) else { throw ProtocolDefect.missingExhale }

        for kind in BreathingPlan.Phase.Kind.allCases where kinds.filter({ $0 == kind }).count > 1 {
            throw ProtocolDefect.repeatedPhase(kind)
        }

        let canonical = BreathingPlan.Phase.Kind.allCases
        let ranks = kinds.compactMap { canonical.firstIndex(of: $0) }
        guard ranks == ranks.sorted() else { throw ProtocolDefect.phasesOutOfOrder }

        for phase in cycle.phases where !MechanicalBounds.phaseDuration.contains(phase.duration) {
            throw ProtocolDefect.durationOutOfBounds(phase.type, phase.duration)
        }
        guard MechanicalBounds.entryDuration.contains(entry.duration) else {
            throw ProtocolDefect.entryOutOfBounds(entry.duration)
        }
        guard MechanicalBounds.exitDuration.contains(exit.duration) else {
            throw ProtocolDefect.exitOutOfBounds(exit.duration)
        }
        guard MechanicalBounds.cycles.contains(self.repeat.cycles) else {
            throw ProtocolDefect.cyclesOutOfBounds(self.repeat.cycles)
        }

        let factor = self.repeat.firstCycleFactor ?? 1
        guard MechanicalBounds.firstCycleFactor.contains(factor) else {
            throw ProtocolDefect.firstCycleFactorOutOfBounds(factor)
        }

        if let tempo = userTempo, !(tempo.min...tempo.max).contains(1) {
            throw ProtocolDefect.tempoRangeExcludesNormal
        }

        guard totalDuration <= MechanicalBounds.totalDuration else {
            throw ProtocolDefect.totalTooLong(totalDuration)
        }
    }

    /// Entry, every cycle including the possibly longer first one, and the exit.
    public var totalDuration: TimeInterval {
        let cycleLength = cycle.phases.reduce(0) { $0 + $1.duration }
        let factor = self.repeat.firstCycleFactor ?? 1
        let cycles = Double(self.repeat.cycles) - 1 + factor
        return entry.duration + cycleLength * cycles + exit.duration
    }
}
