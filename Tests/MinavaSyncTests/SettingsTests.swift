import XCTest
@testable import MinavaSync

private final class OfflineRemote: RemoteDeleting, @unchecked Sendable {
    func deleteEverything() -> Bool { false }
}

private final class ReachableRemote: RemoteDeleting, @unchecked Sendable {
    private(set) var called = false
    func deleteEverything() -> Bool { called = true; return true }
}

final class SettingsTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("minava-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeStore(remote: RemoteDeleting? = nil) -> FileEpisodeStore {
        FileEpisodeStore(url: folder.appendingPathComponent("episodes.json"), remote: remote)
    }

    // MARK: - Изтриване

    /// The promise in docs/ДАННИ.md: local goes at once, and the caller learns whether the
    /// copy in iCloud is still queued.
    func testDeletingOfflineReportsThatTheRemoteCopyIsStillWaiting() throws {
        let store = makeStore(remote: OfflineRemote())
        try Journal(store: store).record(intensity: 3)

        let outcome = try SettingsService(store: store,
                                          preferences: InMemoryPreferences()).deleteEverything()

        XCTAssertEqual(outcome, .remotePending)
        XCTAssertTrue(try store.all().isEmpty, "локалното изчезва веднага")
    }

    func testDeletingWithANetworkReportsComplete() throws {
        let remote = ReachableRemote()
        let store = makeStore(remote: remote)
        try Journal(store: store).record(intensity: 3)

        let outcome = try SettingsService(store: store,
                                          preferences: InMemoryPreferences()).deleteEverything()

        XCTAssertEqual(outcome, .complete)
        XCTAssertTrue(remote.called)
    }

    func testDeletingWithoutSyncNeedsNoRemoteAtAll() throws {
        let store = makeStore()
        try Journal(store: store).record(intensity: 3)
        let outcome = try SettingsService(store: store,
                                          preferences: InMemoryPreferences()).deleteEverything()
        XCTAssertEqual(outcome, .complete)
    }

    func testDeletingTwiceIsHarmless() throws {
        let store = makeStore()
        let settings = SettingsService(store: store, preferences: InMemoryPreferences())
        _ = try settings.deleteEverything()
        XCTAssertNoThrow(try settings.deleteEverything())
        XCTAssertTrue(try store.all().isEmpty)
    }

    // MARK: - Синхронът

    /// Changing your mind about iCloud must never cost you your journal.
    func testTurningSyncOffKeepsEveryRecord() throws {
        let store = makeStore()
        let settings = SettingsService(store: store, preferences: InMemoryPreferences())
        try Journal(store: store).record(intensity: 4)

        settings.setSync(enabled: false)

        XCTAssertFalse(settings.current.syncEnabled)
        XCTAssertEqual(try store.all().count, 1)
    }

    func testVoiceCanBeTurnedOffAndStaysOff() {
        let settings = SettingsService(store: makeStore(),
                                       preferences: InMemoryPreferences())
        settings.setVoice(enabled: false)
        XCTAssertFalse(settings.current.voiceEnabled)
        settings.setSync(enabled: false)
        XCTAssertFalse(settings.current.voiceEnabled, "едната настройка не гаси другата")
    }

    // MARK: - Износ

    func testExportRoundTrips() throws {
        let store = makeStore()
        let journal = Journal(store: store)
        try journal.record(intensity: 2)
        try journal.record(intensity: 5)

        let data = try SettingsService(store: store,
                                       preferences: InMemoryPreferences()).export()
        let restored = try EpisodeExport.decoded(from: data)

        XCTAssertEqual(restored.format, "minava-episodes")
        XCTAssertEqual(restored.version, 1)
        XCTAssertEqual(restored.episodes.count, 2)
        XCTAssertEqual(Set(restored.episodes.map(\.intensity)), [2, 5])
    }

    /// Readable by a person, not only by a program — that is half the reason it exists.
    func testExportIsReadableText() throws {
        let store = makeStore()
        try Journal(store: store).record(intensity: 3)
        let data = try SettingsService(store: store,
                                       preferences: InMemoryPreferences()).export()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.contains("minava-episodes"))
        XCTAssertTrue(text.contains("\n"), "форматиран, не един ред")
    }

    func testExportOfAnEmptyJournalIsStillAValidFile() throws {
        let data = try SettingsService(store: makeStore(),
                                       preferences: InMemoryPreferences()).export()
        XCTAssertEqual(try EpisodeExport.decoded(from: data).episodes.count, 0)
    }

    func testExportFileNameCarriesTheDate() {
        let settings = SettingsService(store: makeStore(), preferences: InMemoryPreferences())
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 4
        let day = Calendar(identifier: .gregorian).date(from: parts)!
        XCTAssertEqual(settings.exportFileName(now: day), "minava-2026-09-04.json")
    }

    // MARK: - Хранилището

    func testRecordsSurviveANewStoreOverTheSameFile() throws {
        try Journal(store: makeStore()).record(intensity: 4)
        XCTAssertEqual(try makeStore().all().count, 1)
    }

    func testEpisodesComeBackNewestFirst() throws {
        let store = makeStore()
        let journal = Journal(store: store)
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        try journal.record(intensity: 1, startedAt: old)
        try journal.record(intensity: 2, startedAt: old.addingTimeInterval(86_400))

        XCTAssertEqual(try store.all().map(\.intensity), [2, 1])
    }

    func testASingleRecordCanBeDeleted() throws {
        let store = makeStore()
        let journal = Journal(store: store)
        let first = try journal.record(intensity: 1)
        try journal.record(intensity: 2)

        try store.delete(id: first.id)

        XCTAssertEqual(try store.all().map(\.intensity), [2])
    }
}

extension SettingsTests {

    // MARK: - Износ, четим и от човек

    private func catalogue() -> TriggerCatalogue {
        TriggerCatalogue(triggers: [
            .init(id: "crowd", bg: "тълпа", en: "crowd"),
            .init(id: "work", bg: "работа", en: "work")
        ])
    }

    func testTextExportIsReadableAndNamesTheTriggersInBulgarian() throws {
        let store = makeStore()
        let journal = Journal(store: store, catalogue: catalogue())
        try journal.record(intensity: 4, triggers: ["crowd", "work"],
                           startedAt: Date(timeIntervalSince1970: 1_772_000_000))

        let text = try SettingsService(store: store,
                                       preferences: InMemoryPreferences(),
                                       catalogue: catalogue()).exportText()

        XCTAssertTrue(text.contains("Дневник на епизодите"))
        XCTAssertTrue(text.contains("сила 4"))
        XCTAssertTrue(text.contains("тълпа, работа"), "етикетите се превеждат: \(text)")
        XCTAssertFalse(text.contains("crowd"), "идентификаторите не се показват на човек")
    }

    /// Непознат етикет остава като идентификатор, вместо да изчезне безшумно.
    func testAnUnknownTriggerSurvivesTheExport() throws {
        let store = makeStore()
        try Journal(store: store).record(intensity: 2, triggers: ["нещо-ново"])
        let text = try SettingsService(store: store,
                                       preferences: InMemoryPreferences()).exportText()
        XCTAssertTrue(text.contains("нещо-ново"))
    }

    func testTextExportOfAnEmptyJournalSaysSo() throws {
        let text = try SettingsService(store: makeStore(),
                                       preferences: InMemoryPreferences()).exportText()
        XCTAssertTrue(text.contains("(няма записи)"))
        XCTAssertTrue(text.contains("Записи: 0"))
    }

    func testTextExportIsNewestFirst() throws {
        let store = makeStore()
        let journal = Journal(store: store)
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        try journal.record(intensity: 1, startedAt: old)
        try journal.record(intensity: 5, startedAt: old.addingTimeInterval(86_400))

        let text = try SettingsService(store: store,
                                       preferences: InMemoryPreferences()).exportText()
        let five = try XCTUnwrap(text.range(of: "сила 5"))
        let one = try XCTUnwrap(text.range(of: "сила 1"))
        XCTAssertTrue(five.lowerBound < one.lowerBound)
    }

    func testBothFileNamesCarryTheDate() {
        let settings = SettingsService(store: makeStore(), preferences: InMemoryPreferences())
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 4
        let day = Calendar(identifier: .gregorian).date(from: parts)!
        XCTAssertEqual(settings.exportFileName(now: day), "minava-2026-09-04.json")
        XCTAssertEqual(settings.exportTextFileName(now: day), "minava-2026-09-04.txt")
    }
}
