import XCTest
@testable import MinavaCore

final class MechanicalBoundsTests: XCTestCase {

    func testTheFillerPlanIsExecutable() throws {
        XCTAssertNoThrow(try Fixtures.plan().checkMechanicalBounds())
    }

    func testCycleWithoutAnInhaleIsRefused() {
        let plan = BreathingPlan(
            entry: .init(duration: 0),
            cycle: .init(phases: [
                .init(type: .holdIn, duration: 2, hapticIntensity: nil),
                .init(type: .exhale, duration: 6, hapticIntensity: nil)
            ]),
            repeat: .init(cycles: 1, firstCycleFactor: nil),
            exit: .init(duration: 2),
            userTempo: nil)
        assertDefect(.missingInhale, from: plan)
    }

    func testCycleWithoutAnExhaleIsRefused() {
        let plan = BreathingPlan(
            entry: .init(duration: 0),
            cycle: .init(phases: [
                .init(type: .inhale, duration: 4, hapticIntensity: nil),
                .init(type: .holdIn, duration: 2, hapticIntensity: nil)
            ]),
            repeat: .init(cycles: 1, firstCycleFactor: nil),
            exit: .init(duration: 2),
            userTempo: nil)
        assertDefect(.missingExhale, from: plan)
    }

    func testPhasesOutOfOrderAreRefused() {
        let plan = BreathingPlan(
            entry: .init(duration: 0),
            cycle: .init(phases: [
                .init(type: .exhale, duration: 6, hapticIntensity: nil),
                .init(type: .inhale, duration: 4, hapticIntensity: nil)
            ]),
            repeat: .init(cycles: 1, firstCycleFactor: nil),
            exit: .init(duration: 2),
            userTempo: nil)
        assertDefect(.phasesOutOfOrder, from: plan)
    }

    func testRepeatedPhaseIsRefused() {
        let plan = BreathingPlan(
            entry: .init(duration: 0),
            cycle: .init(phases: [
                .init(type: .inhale, duration: 4, hapticIntensity: nil),
                .init(type: .inhale, duration: 4, hapticIntensity: nil),
                .init(type: .exhale, duration: 6, hapticIntensity: nil)
            ]),
            repeat: .init(cycles: 1, firstCycleFactor: nil),
            exit: .init(duration: 2),
            userTempo: nil)
        assertDefect(.repeatedPhase(.inhale), from: plan)
    }

    /// Seconds written as milliseconds is the mistake these bounds exist to catch.
    func testAbsurdPhaseDurationIsRefused() {
        assertDefect(.durationOutOfBounds(.inhale, 4000),
                     from: Fixtures.plan(inhale: 4000, cycles: 1))
    }

    func testTooShortPhaseIsRefused() {
        assertDefect(.durationOutOfBounds(.exhale, 0.2),
                     from: Fixtures.plan(exhale: 0.2, cycles: 1))
    }

    func testAbruptExitIsRefused() {
        assertDefect(.exitOutOfBounds(0.4), from: Fixtures.plan(cycles: 1, exit: 0.4))
    }

    func testTooManyCyclesAreRefused() {
        assertDefect(.cyclesOutOfBounds(61), from: Fixtures.plan(cycles: 61))
    }

    func testExerciseLongerThanTwentyMinutesIsRefused() throws {
        let plan = Fixtures.plan(inhale: 20, holdIn: 20, exhale: 20, cycles: 30)
        XCTAssertGreaterThan(plan.totalDuration, 20 * 60)
        assertDefect(.totalTooLong(plan.totalDuration), from: plan)
    }

    func testTempoRangeMustContainNormalSpeed() {
        assertDefect(.tempoRangeExcludesNormal,
                     from: Fixtures.plan(cycles: 1, tempo: (min: 1.05, max: 1.2)))
    }

    // MARK: - Helper

    private func assertDefect(
        _ expected: ProtocolDefect,
        from plan: BreathingPlan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try plan.checkMechanicalBounds(), file: file, line: line) { error in
            XCTAssertEqual(error as? ProtocolDefect, expected, file: file, line: line)
        }
    }
}
