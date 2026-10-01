import XCTest
@testable import MinavaCore

final class ExecutablePracticeTests: XCTestCase {

    private func file(
        id: String = "practice",
        kind: ClinicalProtocol.Kind = .regulation,
        status: ClinicalProtocol.Status = .draft,
        approval: Approval? = nil,
        steps: [String] = ["едно", "две"],
        preparation: [String] = [],
        rounds: Int? = nil,
        sides: [ClinicalProtocol.Side]? = nil,
        measure: ClinicalProtocol.Measure? = nil,
        recovery: String? = nil,
        section: ClinicalProtocol.Section? = .nervousSystem,
        stopRule: String? = nil,
        minutes: Int? = nil
    ) -> ClinicalProtocol {
        ClinicalProtocol(
            id: id,
            version: 1,
            kind: kind,
            status: status,
            approval: approval,
            title: LocalizedText(bg: "Практика"),
            steps: steps.map { GroundingStep(text: LocalizedText(bg: $0), minDuration: 10) },
            preparation: preparation.isEmpty
                ? nil
                : preparation.map { GroundingStep(text: LocalizedText(bg: $0)) },
            section: section,
            estimatedMinutes: minutes,
            stopRule: stopRule.map { LocalizedText(bg: $0) },
            measure: measure,
            rounds: rounds,
            sides: sides,
            recoveryProtocol: recovery)
    }

    private var approved: Approval {
        Approval(approvedBy: .init(name: "Специалист", credentials: "психолог"),
                 approvedAt: "2026-09-01",
                 appliesToVersion: 1,
                 scope: "цялата практика, версия 1")
    }

    // MARK: - Гейтът

    func testAnUnapprovedPracticeDoesNotRunInRelease() {
        XCTAssertThrowsError(try ExecutablePractice(file(), build: .release)) { error in
            XCTAssertEqual(error as? ProtocolGateError,
                           .unapprovedInRelease(id: "practice", version: 1))
        }
    }

    func testAnUnapprovedPracticeRunsInDevelopmentButIsMarked() throws {
        let practice = try ExecutablePractice(file(), build: .debug)
        XCTAssertTrue(practice.isProvisional)
    }

    /// The reason the personal build exists: the author uses the app, nobody else receives it.
    func testAnUnapprovedPracticeRunsInAPersonalBuildAndIsStillMarked() throws {
        let practice = try ExecutablePractice(file(), build: .personal)
        XCTAssertTrue(practice.isProvisional,
                      "личният билд не прави неодобреното одобрено — само го пуска")
    }

    func testAnApprovedPracticeIsNotProvisional() throws {
        let practice = try ExecutablePractice(
            file(status: .approved, approval: approved), build: .release)
        XCTAssertFalse(practice.isProvisional)
    }

    func testABreathingProtocolCannotEnterThroughThisDoor() {
        let breathing = ClinicalProtocol(
            id: "breath", version: 1, kind: .breathing, status: .draft, approval: nil,
            title: LocalizedText(bg: "Дишане"), breathing: Fixtures.plan())

        XCTAssertThrowsError(try ExecutablePractice(breathing, build: .debug)) { error in
            XCTAssertEqual(error as? ProtocolGateError, .notAPractice(id: "breath"))
        }
    }

    func testAPracticeWithoutStepsIsRefused() {
        XCTAssertThrowsError(try ExecutablePractice(file(steps: []), build: .debug)) { error in
            XCTAssertEqual(error as? ProtocolGateError, .structural(id: "practice",
                                                                    .missingSteps))
        }
    }

    /// Two independent sources warn that challenging without a way back into regulation can
    /// make things worse. The file is refused rather than run.
    func testAnExposureWithoutRecoveryIsRefused() {
        let exposure = file(id: "challenge", kind: .exposure, recovery: nil)
        XCTAssertThrowsError(try ExecutablePractice(exposure, build: .debug)) { error in
            XCTAssertEqual(error as? ProtocolGateError,
                           .structural(id: "challenge", .exposureWithoutRecovery))
        }
    }

    func testAnExposureWithRecoveryIsAccepted() throws {
        let exposure = file(id: "challenge", kind: .exposure, recovery: "calm-down")
        let practice = try ExecutablePractice(exposure, build: .debug)
        XCTAssertEqual(practice.recoveryProtocol, "calm-down")
    }

    // MARK: - Редът на стъпките

    func testASimplePracticeIsJustItsSteps() throws {
        let practice = try ExecutablePractice(file(), build: .debug)
        XCTAssertEqual(practice.sequence.map(\.text.bg), ["едно", "две"])
        XCTAssertEqual(practice.rounds, 1)
        XCTAssertTrue(practice.sides.isEmpty)
    }

    func testRoundsRepeatTheStepsAndAreNumbered() throws {
        let practice = try ExecutablePractice(file(rounds: 3), build: .debug)

        XCTAssertEqual(practice.sequence.count, 6)
        XCTAssertEqual(practice.sequence.map(\.round), [1, 1, 2, 2, 3, 3])
    }

    func testSidesRunInTheOrderTheFileGivesThem() throws {
        let practice = try ExecutablePractice(
            file(steps: ["завърти очите"], sides: [.right, .left]), build: .debug)

        XCTAssertEqual(practice.sequence.compactMap(\.side), [.right, .left])
    }

    func testSidesAndRoundsMultiply() throws {
        let practice = try ExecutablePractice(
            file(steps: ["а", "б"], rounds: 2, sides: [.right, .left]), build: .debug)

        XCTAssertEqual(practice.sequence.count, 8)
        XCTAssertEqual(practice.sequence.map(\.round), [1, 1, 1, 1, 2, 2, 2, 2])
    }

    /// Getting into position is not part of the exercise. Nine rounds must not mean being
    /// told nine times where to put your hands.
    func testPreparationIsShownOnceAndBelongsToNoRound() throws {
        let practice = try ExecutablePractice(
            file(steps: ["вдишай"], preparation: ["седни изправено"], rounds: 9),
            build: .debug)

        let texts = practice.sequence.map(\.text.bg)
        XCTAssertEqual(texts.filter { $0 == "седни изправено" }.count, 1)
        XCTAssertEqual(texts.filter { $0 == "вдишай" }.count, 9)
        XCTAssertEqual(practice.sequence.first?.round, 0)
        XCTAssertEqual(practice.sequence.first?.text.bg, "седни изправено")
    }

    func testTheShortestDurationCountsEveryRound() throws {
        let practice = try ExecutablePractice(file(steps: ["а", "б"], rounds: 3),
                                              build: .debug)
        XCTAssertEqual(practice.shortestDuration, 60, accuracy: 0.001)
    }

    func testTheMeasureTravelsWithThePractice() throws {
        let practice = try ExecutablePractice(file(measure: .activation), build: .debug)
        XCTAssertEqual(practice.measure, .activation)
    }

    // MARK: - Секцията и правилото за спиране

    /// Практика без секция не се показва никъде — каталогът е групиран.
    func testAPracticeWithoutASectionIsRefused() {
        XCTAssertThrowsError(try ExecutablePractice(file(section: nil), build: .debug)) {
            XCTAssertEqual($0 as? ProtocolGateError, .structural(id: "practice",
                                                                 .missingSection))
        }
    }

    /// Правилото от docs/ТРЕВОЖНОСТ.md: около 8% обща честота на нежеланите събития при
    /// медитация, а най-честото от тях е самата тревожност. Без изход не се предлага.
    func testAnAttentionPracticeWithoutAStopRuleIsRefused() {
        let meditation = file(section: .attention)
        XCTAssertThrowsError(try ExecutablePractice(meditation, build: .debug)) {
            XCTAssertEqual($0 as? ProtocolGateError,
                           .structural(id: "practice", .attentionWithoutStopRule))
        }
    }

    func testAnAttentionPracticeWithAStopRuleCarriesIt() throws {
        let practice = try ExecutablePractice(
            file(section: .attention, stopRule: "Стане ли по-тежко, спри."), build: .debug)
        XCTAssertEqual(practice.section, .attention)
        XCTAssertEqual(practice.stopRule?.bg, "Стане ли по-тежко, спри.")
    }

    /// Правилото важи само там, където трябва: другите секции не го искат.
    func testOtherSectionsDoNotNeedAStopRule() {
        for section in ClinicalProtocol.Section.allCases where section != .attention {
            let subject = file(recovery: section == .challenge ? "calm-down" : nil,
                               section: section)
            XCTAssertNil(subject.structuralDefect(), "\(section)")
        }
    }

    func testTheDurationTravelsWithThePractice() throws {
        XCTAssertEqual(try ExecutablePractice(file(minutes: 3), build: .debug)
                        .estimatedMinutes, 3)
    }
}
