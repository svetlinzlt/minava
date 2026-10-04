import XCTest
@testable import MinavaSync

final class LadderTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("minava-ladder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeStore() -> FileLadderStore {
        FileLadderStore(url: folder.appendingPathComponent("ladder.json"))
    }

    private func settings(ladder: LadderStoring?) -> SettingsService {
        SettingsService(store: FileEpisodeStore(url: folder.appendingPathComponent("e.json")),
                        preferences: InMemoryPreferences(),
                        ladder: ladder)
    }

    // MARK: - Една стълба, не колекция

    /// Решението: едно стъпало на една стълба. Напредък по няколко стълби е колекция,
    /// колекцията става история, а историята е графиката, която docs/ДАННИ.md пази.
    func testStartingAnotherLadderReplacesTheFirst() throws {
        let store = makeStore()
        try store.record(.init(protocolID: "ladder-crowd", rung: 3), rungCount: 7)
        try store.record(.init(protocolID: "ladder-transport", rung: 0), rungCount: 5)

        let current = try XCTUnwrap(store.current())
        XCTAssertEqual(current.protocolID, "ladder-transport")
        XCTAssertEqual(current.rung, 0)
    }

    func testTheFileHoldsOneObjectNotAList() throws {
        let store = makeStore()
        try store.record(.init(protocolID: "ladder-crowd", rung: 1), rungCount: 7)

        let data = try Data(contentsOf: folder.appendingPathComponent("ladder.json"))
        let json = try JSONSerialization.jsonObject(with: data)

        XCTAssertTrue(json is [String: Any], "очаква се една стълба, а не колекция")
        XCTAssertFalse(json is [Any])
    }

    func testNothingIsStoredBeforeTheFirstRung() throws {
        XCTAssertNil(try makeStore().current())
    }

    // MARK: - Границите

    func testARungOutsideTheLadderIsRefused() {
        let store = makeStore()
        for rung in [-1, 7, 99] {
            XCTAssertThrowsError(
                try store.record(.init(protocolID: "ladder-crowd", rung: rung), rungCount: 7)
            ) { XCTAssertEqual($0 as? LadderError, .rungOutOfRange(rung)) }
        }
        XCTAssertNil(try? store.current() ?? nil)
    }

    func testTheEdgesAreAllowed() throws {
        let store = makeStore()
        XCTAssertNoThrow(try store.record(.init(protocolID: "l", rung: 0), rungCount: 7))
        XCTAssertNoThrow(try store.record(.init(protocolID: "l", rung: 6), rungCount: 7))
    }

    /// Стълба, недокосната от месец, не е мястото, където човек е сега.
    func testAnUntouchedLadderGoesStale() {
        let old = LadderProgress(protocolID: "l", rung: 2,
                                 updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(old.isStale())
        XCTAssertFalse(LadderProgress(protocolID: "l", rung: 2).isStale())
    }

    // MARK: - Изтриването

    /// „Изтрий всичко“ трябва да значи всичко — стълбата също.
    func testDeletingEverythingClearsTheLadder() throws {
        let store = makeStore()
        try store.record(.init(protocolID: "ladder-crowd", rung: 4), rungCount: 7)

        _ = try settings(ladder: store).deleteEverything()

        XCTAssertNil(try store.current())
    }

    func testEverythingWorksWithoutALadderStore() throws {
        let service = settings(ladder: nil)
        XCTAssertNil(try service.currentLadder())
        XCTAssertNoThrow(try service.recordLadder(protocolID: "l", rung: 0, rungCount: 3))
        XCTAssertNoThrow(try service.deleteEverything())
    }

    func testTheServiceMovesTheLadder() throws {
        let service = settings(ladder: makeStore())
        try service.recordLadder(protocolID: "ladder-crowd", rung: 2, rungCount: 7)

        let current = try XCTUnwrap(try service.currentLadder())
        XCTAssertEqual(current.protocolID, "ladder-crowd")
        XCTAssertEqual(current.rung, 2)
    }
}
