import XCTest
@testable import MinavaSync

final class ActivationTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("minava-activation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeStore() -> FileActivationStore {
        FileActivationStore(url: folder.appendingPathComponent("activation.json"))
    }

    private func settings(activation: ActivationStoring?) -> SettingsService {
        SettingsService(store: FileEpisodeStore(url: folder.appendingPathComponent("e.json")),
                        preferences: InMemoryPreferences(),
                        activation: activation)
    }

    // MARK: - Едно място, което се презаписва

    /// Решението: пази се само последната промяна. Не "показва се последната от списък" —
    /// списък изобщо няма, за да не може да се превърне в график.
    func testRecordingTwiceKeepsOnlyTheSecond() throws {
        let store = makeStore()
        try store.record(.init(before: 8, after: 5, protocolID: "orienting"))
        try store.record(.init(before: 6, after: 2, protocolID: "cold-water"))

        let latest = try XCTUnwrap(store.latest())
        XCTAssertEqual(latest.before, 6)
        XCTAssertEqual(latest.after, 2)
        XCTAssertEqual(latest.protocolID, "cold-water")
    }

    /// Файлът съдържа един обект, не масив. Това е разликата между „пазим последното“ и
    /// „пазим всичко и показваме последното“.
    func testTheFileHoldsOneObjectNotAList() throws {
        let store = makeStore()
        try store.record(.init(before: 7, after: 3, protocolID: "salamander"))

        let data = try Data(contentsOf: folder.appendingPathComponent("activation.json"))
        let json = try JSONSerialization.jsonObject(with: data)

        XCTAssertTrue(json is [String: Any], "очаква се един запис, а не колекция")
        XCTAssertFalse(json is [Any])
    }

    func testNothingIsStoredBeforeTheFirstReading() throws {
        XCTAssertNil(try makeStore().latest())
    }

    // MARK: - Границите

    func testRatingsOutsideZeroToTenAreRefused() {
        let store = makeStore()
        for value in [-1, 11, 99] {
            XCTAssertThrowsError(
                try store.record(.init(before: value, after: 3, protocolID: "x"))
            ) { XCTAssertEqual($0 as? ActivationError, .outOfRange(value)) }
            XCTAssertThrowsError(
                try store.record(.init(before: 3, after: value, protocolID: "x"))
            ) { XCTAssertEqual($0 as? ActivationError, .outOfRange(value)) }
        }
        XCTAssertNil(try? store.latest() ?? nil)
    }

    func testTheEdgesAreAllowed() throws {
        let store = makeStore()
        XCTAssertNoThrow(try store.record(.init(before: 0, after: 10, protocolID: "x")))
        XCTAssertNoThrow(try store.record(.init(before: 10, after: 0, protocolID: "x")))
    }

    // MARK: - Какво показва

    func testChangeIsNegativeWhenCalmer() {
        XCTAssertEqual(ActivationReading(before: 8, after: 3, protocolID: "x").change, -5)
        XCTAssertEqual(ActivationReading(before: 3, after: 3, protocolID: "x").change, 0)
        XCTAssertEqual(ActivationReading(before: 2, after: 5, protocolID: "x").change, 3)
    }

    /// Стара стойност не бива да се показва, все едно е от днес.
    func testAnOldReadingIsStale() {
        let old = ActivationReading(before: 8, after: 4, protocolID: "x",
                                    recordedAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(old.isStale())

        let fresh = ActivationReading(before: 8, after: 4, protocolID: "x")
        XCTAssertFalse(fresh.isStale())
    }

    // MARK: - Изтриването и износът

    /// „Изтрий всичко“ трябва да значи всичко, иначе думата лъже на екран, на който някой
    /// се доверява.
    func testDeletingEverythingClearsTheReading() throws {
        let store = makeStore()
        try store.record(.init(before: 9, after: 4, protocolID: "x"))

        _ = try settings(activation: store).deleteEverything()

        XCTAssertNil(try store.latest())
    }

    func testTheReadingTravelsWithTheExport() throws {
        let store = makeStore()
        let service = settings(activation: store)
        try service.recordActivation(before: 7, after: 2, protocolID: "cold-water")

        let restored = try EpisodeExport.decoded(from: try service.export())
        XCTAssertEqual(restored.activation?.before, 7)
        XCTAssertEqual(restored.activation?.after, 2)

        let text = try service.exportText()
        XCTAssertTrue(text.contains("7 → 2"), text)
    }

    func testAnExportWithoutAReadingSaysNothingAboutIt() throws {
        let service = settings(activation: makeStore())
        XCTAssertNil(try EpisodeExport.decoded(from: try service.export()).activation)
        XCTAssertFalse(try service.exportText().contains("Последно измерване"))
    }

    /// Приложение без скала продължава да работи — тя е допълнение, не условие.
    func testEverythingWorksWithoutAnActivationStore() throws {
        let service = settings(activation: nil)
        XCTAssertNil(try service.latestActivation())
        XCTAssertNoThrow(try service.recordActivation(before: 5, after: 1, protocolID: "x"))
        XCTAssertNoThrow(try service.deleteEverything())
    }
}
