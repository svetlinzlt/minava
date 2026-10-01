import XCTest
@testable import MinavaCore
@testable import MinavaPanic

final class PracticeSessionTests: XCTestCase {

    private var events: [PracticeSession.Event] = []

    override func setUp() {
        super.setUp()
        events = []
    }

    private func make(
        kind: ClinicalProtocol.Kind = .regulation,
        steps: [(String, Double?)] = [("едно", 10), ("две", 10)],
        preparation: [String] = [],
        rounds: Int? = nil,
        sides: [ClinicalProtocol.Side]? = nil,
        measure: ClinicalProtocol.Measure? = nil,
        recovery: String? = nil
    ) -> PracticeSession {
        let file = ClinicalProtocol(
            id: "practice", version: 1, kind: kind, status: .draft, approval: nil,
            title: LocalizedText(bg: "Практика"),
            steps: steps.map {
                GroundingStep(text: LocalizedText(bg: $0.0), minDuration: $0.1)
            },
            preparation: preparation.isEmpty
                ? nil
                : preparation.map { GroundingStep(text: LocalizedText(bg: $0)) },
            section: kind == .exposure ? .challenge : .nervousSystem,
            measure: measure, rounds: rounds, sides: sides, recoveryProtocol: recovery)

        let practice = try! ExecutablePractice(file, build: .debug)
        return PracticeSession(practice: practice) { self.events.append($0) }
    }

    // MARK: - Редът

    func testAPracticeWithoutAMeasureStartsStraightOnTheFirstStep() {
        let session = make()
        session.start(now: 0)

        XCTAssertEqual(session.stage, .running(index: 0))
        XCTAssertEqual(session.currentStep?.text.bg, "едно")
        XCTAssertFalse(session.asksForRating)
    }

    func testAPracticeWithAMeasureAsksFirst() {
        let session = make(measure: .activation)
        session.start(now: 0)

        XCTAssertEqual(session.stage, .ratingBefore)
        XCTAssertEqual(events, [.started, .asksRating(before: true)])
        XCTAssertNil(session.currentStep, "нищо не се показва, преди да е отговорено")
    }

    func testTheWholeLoopEndsWithAChange() {
        let session = make(steps: [("едно", nil)], measure: .activation)
        session.start(now: 0)
        session.rate(8, now: 0)

        XCTAssertEqual(session.stage, .running(index: 0))
        XCTAssertTrue(session.advance(now: 0))
        XCTAssertEqual(session.stage, .ratingAfter)

        session.rate(3, now: 0)
        XCTAssertEqual(session.stage, .finished)
        XCTAssertEqual(session.change, -5)
        XCTAssertEqual(events.last, .finished(change: -5))
    }

    func testARatingOutsideTheScaleIsRefusedRatherThanClamped() {
        let session = make(measure: .activation)
        session.start(now: 0)

        XCTAssertFalse(session.rate(11, now: 0))
        XCTAssertFalse(session.rate(-1, now: 0))
        XCTAssertEqual(session.stage, .ratingBefore)
        XCTAssertNil(session.before)

        XCTAssertTrue(session.rate(10, now: 0))
        XCTAssertEqual(session.before, 10)
    }

    func testRatingIsIgnoredWhenNothingIsBeingAsked() {
        let session = make()
        session.start(now: 0)
        XCTAssertFalse(session.rate(5, now: 0))
        XCTAssertNil(session.before)
    }

    // MARK: - Минимумът е под, не краен срок

    func testTheButtonIsHeldUntilTheMinimumHasPassed() {
        let session = make(steps: [("едно", 10), ("две", nil)])
        session.start(now: 100)

        XCTAssertFalse(session.canAdvance(now: 104))
        XCTAssertEqual(session.remainingOnStep(now: 104), 6, accuracy: 0.001)
        XCTAssertFalse(session.advance(now: 104), "стъпката не се прескача")
        XCTAssertEqual(session.stage, .running(index: 0))

        XCTAssertTrue(session.canAdvance(now: 110))
        XCTAssertEqual(session.remainingOnStep(now: 110), 0)
        XCTAssertTrue(session.advance(now: 110))
        XCTAssertEqual(session.currentStep?.text.bg, "две")
    }

    /// Никой не се бърза: минимумът минава и нищо не се случва само по себе си.
    func testNothingMovesOnItsOwnAfterTheMinimum() {
        let session = make(steps: [("едно", 5), ("две", nil)])
        session.start(now: 0)

        XCTAssertTrue(session.canAdvance(now: 5_000))
        XCTAssertEqual(session.stage, .running(index: 0),
                       "изчакването отключва бутона, не придвижва упражнението")
    }

    func testAStepWithoutAMinimumIsAlwaysReady() {
        let session = make(steps: [("едно", nil)])
        session.start(now: 0)
        XCTAssertTrue(session.canAdvance(now: 0))
    }

    /// Минимумът се брои от появата на стъпката, не от началото на упражнението.
    func testTheMinimumRestartsWithEveryStep() {
        let session = make(steps: [("едно", 10), ("две", 10)])
        session.start(now: 0)
        session.advance(now: 10)

        XCTAssertFalse(session.canAdvance(now: 15))
        XCTAssertTrue(session.canAdvance(now: 20))
    }

    // MARK: - Кръгове, страни и подготовка

    func testTheSessionWalksEveryRoundAndSide() {
        let session = make(steps: [("завърти очите", nil)],
                           preparation: ["седни изправено"],
                           rounds: 2, sides: [.right, .left])
        session.start(now: 0)

        var seen: [String] = []
        while case .running = session.stage {
            seen.append(session.currentStep!.text.bg)
            session.advance(now: 0)
        }

        XCTAssertEqual(seen.count, 5, "една подготовка плюс две страни по два кръга")
        XCTAssertEqual(seen.first, "седни изправено")
        XCTAssertEqual(session.stepCount, 5)
    }

    func testPreparationIsNotCountedAsARound() {
        let session = make(steps: [("вдишай", nil)], preparation: ["седни"], rounds: 3)
        session.start(now: 0)

        XCTAssertEqual(session.currentStep?.round, 0)
        session.advance(now: 0)
        XCTAssertEqual(session.currentStep?.round, 1)
    }

    func testTheStepEventKnowsWhereItIsInTheWhole() {
        let session = make(steps: [("едно", nil), ("две", nil)])
        session.start(now: 0)
        session.advance(now: 0)

        guard case .step(_, let index, let total)? = events.last else {
            return XCTFail("очаква се стъпка: \(events)")
        }
        XCTAssertEqual(index, 1)
        XCTAssertEqual(total, 2)
    }

    // MARK: - Спиране

    /// Упражнение, от което не може да се излезе, е капан.
    func testStoppingIsAlwaysPossibleAndKeepsNothing() {
        let session = make(steps: [("едно", 60)], measure: .activation)
        session.start(now: 0)
        session.rate(9, now: 0)
        session.stop()

        XCTAssertEqual(session.stage, .finished)
        XCTAssertNil(session.before, "половин измерване не е измерване")
        XCTAssertNil(session.change)
        XCTAssertEqual(events.last, .stopped)
    }

    func testStoppingTwiceChangesNothing() {
        let session = make()
        session.start(now: 0)
        session.stop()
        let count = events.count
        session.stop()
        XCTAssertEqual(events.count, count)
    }

    // MARK: - Пътят обратно след предизвикване

    /// Предизвикване, което свършва и връща човек в деня му, е точно онова, срещу което
    /// предупреждават и книгата, и литературата. Затова връщането е събитие, а не съвет.
    func testAnExposureEndsWithTheWayBack() {
        let session = make(kind: .exposure, steps: [("усилие", nil)], recovery: "calm-down")
        session.start(now: 0)
        session.advance(now: 0)

        XCTAssertEqual(events.last, .mustRecover(protocolID: "calm-down"))
    }

    func testARegulationPracticeDoesNotDemandRecovery() {
        let session = make(steps: [("едно", nil)])
        session.start(now: 0)
        session.advance(now: 0)

        XCTAssertEqual(events.last, .finished(change: nil))
    }

    /// Прекъснатото предизвикване иска връщането още повече, не по-малко.
    func testAStoppedExposureStillAsksForTheWayBack() {
        let session = make(kind: .exposure, steps: [("усилие", 60)], recovery: "calm-down")
        session.start(now: 0)
        session.stop()

        XCTAssertTrue(events.contains(.mustRecover(protocolID: "calm-down")),
                      "спряно предизвикване не бива да остави човек вдигнат: \(events)")
    }

    // MARK: - Знакът

    func testUnapprovedContentIsMarked() {
        XCTAssertTrue(make().isProvisional)
    }
}
