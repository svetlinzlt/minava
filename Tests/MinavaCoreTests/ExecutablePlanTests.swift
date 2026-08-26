import XCTest
@testable import MinavaCore

final class ExecutablePlanTests: XCTestCase {

    private func file(
        status: ClinicalProtocol.Status,
        approval: Approval?,
        version: Int = 1,
        kind: ClinicalProtocol.Kind = .breathing,
        plan: BreathingPlan? = nil
    ) -> ClinicalProtocol {
        ClinicalProtocol(
            id: "test-breathing",
            version: version,
            kind: kind,
            status: status,
            approval: approval,
            title: LocalizedText(bg: "Тест"),
            breathing: kind == .breathing ? (plan ?? Fixtures.plan()) : nil)
    }

    private func approval(for version: Int) -> Approval {
        Approval(
            approvedBy: .init(name: "Тест Тестов", credentials: "клиничен психолог"),
            approvedAt: "2026-09-01",
            appliesToVersion: version,
            scope: "остър епизод при паническо разстройство")
    }

    // MARK: - Гейтът

    func testReleaseRefusesAnUnapprovedProtocol() {
        XCTAssertThrowsError(
            try ExecutablePlan(file(status: .draft, approval: nil), build: .release)
        ) { error in
            XCTAssertEqual(error as? ProtocolGateError,
                           .unapprovedInRelease(id: "test-breathing", version: 1))
        }
    }

    func testReleaseRefusesApprovalIssuedForAnotherVersion() {
        let stale = file(status: .approved, approval: approval(for: 1), version: 2)
        XCTAssertThrowsError(try ExecutablePlan(stale, build: .release)) { error in
            XCTAssertEqual(error as? ProtocolGateError,
                           .unapprovedInRelease(id: "test-breathing", version: 2))
        }
    }

    func testReleaseAcceptsAnApprovedProtocol() throws {
        let approved = file(status: .approved, approval: approval(for: 1))
        let plan = try ExecutablePlan(approved, build: .release)
        XCTAssertFalse(plan.isProvisional)
        XCTAssertEqual(plan.protocolID, "test-breathing")
    }

    /// Development builds may run unapproved values, but never silently.
    func testDebugAllowsUnapprovedButMarksIt() throws {
        let plan = try ExecutablePlan(file(status: .draft, approval: nil), build: .debug)
        XCTAssertTrue(plan.isProvisional)
    }

    // MARK: - Границите важат и в двата билда

    func testBrokenValuesAreRefusedEvenInDebug() {
        let broken = file(status: .draft, approval: nil, plan: Fixtures.plan(inhale: 4000))
        XCTAssertThrowsError(try ExecutablePlan(broken, build: .debug)) { error in
            XCTAssertEqual(error as? ProtocolGateError,
                           .defect(id: "test-breathing",
                                   .durationOutOfBounds(.inhale, 4000)))
        }
    }

    func testBrokenValuesAreRefusedEvenWhenApproved() {
        let broken = file(status: .approved, approval: approval(for: 1),
                          plan: Fixtures.plan(exit: 0.2))
        XCTAssertThrowsError(try ExecutablePlan(broken, build: .release))
    }

    func testAGroundingProtocolIsNotABreathingPlan() {
        let grounding = file(status: .draft, approval: nil, kind: .grounding)
        XCTAssertThrowsError(try ExecutablePlan(grounding, build: .debug)) { error in
            XCTAssertEqual(error as? ProtocolGateError, .notBreathing(id: "test-breathing"))
        }
    }

    // MARK: - Останалото

    func testTimelineComesFromThePlan() throws {
        let plan = try ExecutablePlan(file(status: .draft, approval: nil), build: .debug)
        XCTAssertEqual(plan.timeline(), Timeline.steps(for: Fixtures.plan()))
        XCTAssertEqual(plan.totalDuration, Fixtures.plan().totalDuration, accuracy: 0.000_001)
    }
}
