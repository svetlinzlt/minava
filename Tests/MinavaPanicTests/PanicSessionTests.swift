import XCTest
import MinavaCore
@testable import MinavaPanic

/// Records what the session asked for, so the tests can check intent without a device.
final class SpyHaptics: HapticPort, @unchecked Sendable {
    private(set) var phases: [BreathingPlan.Phase.Kind] = []
    private(set) var stopCount = 0

    func begin(
        phase: BreathingPlan.Phase.Kind,
        duration: TimeInterval,
        intensity: BreathingPlan.Phase.HapticIntensity?
    ) {
        phases.append(phase)
    }

    func stop() { stopCount += 1 }
}

final class SpyVoice: VoicePort, @unchecked Sendable {
    let isEnabled = true
    private(set) var stopCount = 0
    func speak(_ text: String) {}
    func stop() { stopCount += 1 }
}

final class PanicSessionTests: XCTestCase {

    /// A session cannot be built from raw values — only from a plan that has passed the
    /// gate. In a development build an unapproved protocol is allowed through and marked.
    private func plan(cycles: Int = 2) -> ExecutablePlan {
        let file = ClinicalProtocol(
            id: "test-breathing",
            version: 1,
            kind: .breathing,
            status: .draft,
            approval: nil,
            title: LocalizedText(bg: "Тест"),
            breathing: BreathingPlan(
                entry: .init(duration: 0.6),
                cycle: .init(phases: [
                    .init(type: .inhale, duration: 4, hapticIntensity: .rising),
                    .init(type: .exhale, duration: 6, hapticIntensity: .falling)
                ]),
                repeat: .init(cycles: cycles),
                exit: .init(duration: 4)))
        return try! ExecutablePlan(file, build: .debug)
    }

    func testStartingEmitsStartedAndTheFirstStep() {
        let haptics = SpyHaptics()
        var events: [SessionEvent] = []
        let session = PanicSession(plan: plan(), haptics: haptics) { events.append($0) }

        session.start()

        XCTAssertEqual(events.first, .started)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(session.currentIndex, 0)
    }

    /// The entry is not a breathing phase, so nothing vibrates for it yet.
    func testHapticsFireOnPhasesOnly() {
        let haptics = SpyHaptics()
        let session = PanicSession(plan: plan(cycles: 1), haptics: haptics) { _ in }

        session.start()
        XCTAssertEqual(haptics.phases, [])

        session.update(elapsed: 1)
        XCTAssertEqual(haptics.phases, [.inhale])

        session.update(elapsed: 6)
        XCTAssertEqual(haptics.phases, [.inhale, .exhale])
    }

    func testRepeatedUpdatesWithinOnePhaseDoNotRetrigger() {
        let haptics = SpyHaptics()
        let session = PanicSession(plan: plan(cycles: 1), haptics: haptics) { _ in }

        session.start()
        session.update(elapsed: 1)
        session.update(elapsed: 2)
        session.update(elapsed: 3)

        XCTAssertEqual(haptics.phases, [.inhale])
    }

    /// The exercise ends and the app waits. It has no opinion about how long the person needs.
    func testFinishingWaitsInsteadOfAskingAnything() {
        let haptics = SpyHaptics()
        var events: [SessionEvent] = []
        let session = PanicSession(plan: plan(cycles: 1), haptics: haptics) { events.append($0) }

        session.start()
        session.update(elapsed: session.duration + 1)

        XCTAssertEqual(events.last, .finishedWaiting)
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(haptics.stopCount, 1)
    }

    func testUpdatesAfterTheEndAreIgnored() {
        let haptics = SpyHaptics()
        let session = PanicSession(plan: plan(cycles: 1), haptics: haptics) { _ in }

        session.start()
        session.update(elapsed: session.duration + 1)
        session.update(elapsed: session.duration + 2)

        XCTAssertEqual(haptics.stopCount, 1)
    }

    /// Help leaves immediately. Nothing is asked and nothing is confirmed.
    func testHelpStopsEverythingAtOnce() {
        let haptics = SpyHaptics()
        let voice = SpyVoice()
        var events: [SessionEvent] = []
        let session = PanicSession(plan: plan(), haptics: haptics, voice: voice) {
            events.append($0)
        }

        session.start()
        session.update(elapsed: 1)
        session.handOverToHelp()

        XCTAssertEqual(events.last, .handedOverToHelp)
        XCTAssertEqual(haptics.stopCount, 1)
        XCTAssertEqual(voice.stopCount, 1)
        XCTAssertTrue(session.isFinished)
    }

    func testDurationMatchesTheTimeline() {
        let session = PanicSession(plan: plan(cycles: 3), haptics: SpyHaptics()) { _ in }
        // 0.6 + 10 × 3 + 4
        XCTAssertEqual(session.duration, 34.6, accuracy: 0.000_001)
    }
}

extension PanicSessionTests {

    /// A development build carries the mark; the interface must show it.
    func testSessionKnowsItIsRunningUnapprovedValues() {
        let session = PanicSession(plan: plan(), haptics: SpyHaptics()) { _ in }
        XCTAssertTrue(session.isProvisional)
        XCTAssertEqual(session.protocolID, "test-breathing")
        XCTAssertEqual(session.protocolVersion, 1)
    }
}
