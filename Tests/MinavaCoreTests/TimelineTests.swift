import XCTest
@testable import MinavaCore

final class TimelineTests: XCTestCase {

    func testStepsCoverEntryEveryCycleAndExit() {
        let steps = Timeline.steps(for: Fixtures.plan())

        XCTAssertEqual(steps.count, 1 + 3 * 5 + 1)
        XCTAssertEqual(steps.first?.kind, .entry)
        XCTAssertEqual(steps.last?.kind, .exit)
        XCTAssertEqual(steps[1].kind, .phase(.inhale))
        XCTAssertEqual(steps[1].cycle, 0)
        XCTAssertNil(steps.first?.cycle)
        XCTAssertNil(steps.last?.cycle)
    }

    func testStepsAreContiguousWithNoGapAndNoOverlap() {
        let steps = Timeline.steps(for: Fixtures.plan())
        for (earlier, later) in zip(steps, steps.dropFirst()) {
            XCTAssertEqual(earlier.end, later.start, accuracy: 0.000_001,
                           "пропуск или застъпване между стъпките")
        }
        XCTAssertEqual(steps.first?.start, 0)
    }

    func testTotalDurationMatchesThePlan() {
        let plan = Fixtures.plan()
        let steps = Timeline.steps(for: plan)
        XCTAssertEqual(steps.last?.end ?? 0, plan.totalDuration, accuracy: 0.000_001)
        // 0.6 + 12 × 5 + 4
        XCTAssertEqual(plan.totalDuration, 64.6, accuracy: 0.000_001)
    }

    /// The same plan must yield the same seconds every time. Without that the engine cannot
    /// be tested and we cannot say afterwards what a person actually received.
    func testEngineIsDeterministic() {
        let plan = Fixtures.plan()
        XCTAssertEqual(Timeline.steps(for: plan), Timeline.steps(for: plan))
    }

    func testFirstCycleCanBeLongerWithoutAffectingTheRest() {
        let steps = Timeline.steps(for: Fixtures.plan(cycles: 3, firstCycleFactor: 1.5))
        let inhales = steps.filter { $0.kind == .phase(.inhale) }

        XCTAssertEqual(inhales.count, 3)
        XCTAssertEqual(inhales[0].duration, 6, accuracy: 0.000_001)
        XCTAssertEqual(inhales[1].duration, 4, accuracy: 0.000_001)
        XCTAssertEqual(inhales[2].duration, 4, accuracy: 0.000_001)
    }

    func testEntryIsOmittedWhenItHasNoDuration() {
        let steps = Timeline.steps(for: Fixtures.plan(entry: 0))
        XCTAssertEqual(steps.first?.kind, .phase(.inhale))
        XCTAssertFalse(steps.contains { $0.kind == .entry })
    }

    func testHoldPhaseCanBeOmitted() {
        let steps = Timeline.steps(for: Fixtures.plan(holdIn: nil, cycles: 1))
        XCTAssertFalse(steps.contains { $0.kind == .phase(.holdIn) })
        // Влизане, вдишване, издишване, излизане.
        XCTAssertEqual(steps.count, 4)
    }

    func testHapticShapeTravelsWithTheStep() {
        let steps = Timeline.steps(for: Fixtures.plan(cycles: 1))
        XCTAssertEqual(steps.first { $0.kind == .phase(.inhale) }?.hapticIntensity, .rising)
        XCTAssertEqual(steps.first { $0.kind == .phase(.exhale) }?.hapticIntensity, .falling)
        XCTAssertNil(steps.first?.hapticIntensity)
    }

    // MARK: - Tempo

    func testTempoIsIgnoredWhenTheProtocolDoesNotAllowIt() {
        let plan = Fixtures.plan(cycles: 1)
        XCTAssertEqual(Timeline.steps(for: plan, tempo: 0.8),
                       Timeline.steps(for: plan, tempo: 1))
    }

    func testTempoIsClampedToTheAllowedRange() {
        let plan = Fixtures.plan(cycles: 1, tempo: (min: 0.8, max: 1.2))
        XCTAssertEqual(Timeline.clampedTempo(0.5, plan: plan), 0.8)
        XCTAssertEqual(Timeline.clampedTempo(9, plan: plan), 1.2)
        XCTAssertEqual(Timeline.clampedTempo(1.1, plan: plan), 1.1)
    }

    func testSlowerTempoLengthensThePhases() {
        let plan = Fixtures.plan(cycles: 1, tempo: (min: 0.8, max: 1.2))
        let slower = Timeline.steps(for: plan, tempo: 1.2)
        XCTAssertEqual(slower.first { $0.kind == .phase(.inhale) }?.duration ?? 0,
                       4.8, accuracy: 0.000_001)
    }

    // MARK: - Lookup

    func testStepAtMomentFindsTheRightPhase() {
        let steps = Timeline.steps(for: Fixtures.plan())
        XCTAssertEqual(Timeline.step(at: 0.1, in: steps)?.kind, .entry)
        XCTAssertEqual(Timeline.step(at: 1, in: steps)?.kind, .phase(.inhale))
        XCTAssertEqual(Timeline.step(at: 6, in: steps)?.kind, .phase(.holdIn))
        XCTAssertNil(Timeline.step(at: 999, in: steps))
    }

    /// A boundary belongs to the phase that is starting, never to the one that just ended.
    func testBoundaryBelongsToTheStartingPhase() {
        let steps = Timeline.steps(for: Fixtures.plan())
        let inhale = steps[1]
        XCTAssertEqual(Timeline.step(at: inhale.start, in: steps)?.kind, .phase(.inhale))
        XCTAssertEqual(Timeline.step(at: inhale.end, in: steps)?.kind, .phase(.holdIn))
    }
}
