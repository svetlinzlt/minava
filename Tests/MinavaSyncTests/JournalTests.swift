import XCTest
@testable import MinavaSync

final class JournalTests: XCTestCase {

    private var folder: URL!
    private var store: FileEpisodeStore!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("minava-journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store = FileEpisodeStore(url: folder.appendingPathComponent("episodes.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var parts = DateComponents()
        parts.year = year; parts.month = month; parts.day = day; parts.hour = 12
        return Calendar(identifier: .gregorian).date(from: parts)!
    }

    // MARK: - Записът

    /// The whole design of the entry rests on this: one required input.
    func testOneNumberIsEnoughToRecordAnEpisode() throws {
        let journal = Journal(store: store)
        let episode = try journal.record(intensity: 3)

        XCTAssertEqual(episode.intensity, 3)
        XCTAssertTrue(episode.triggers.isEmpty)
        XCTAssertEqual(try journal.episodes().count, 1)
    }

    func testIntensityOutsideOneToFiveIsRefused() {
        let journal = Journal(store: store)
        for value in [0, 6, -1, 99] {
            XCTAssertThrowsError(try journal.record(intensity: value)) { error in
                XCTAssertEqual(error as? JournalError, .intensityOutOfRange(value))
            }
        }
        XCTAssertEqual(try? journal.episodes().count, 0)
    }

    func testTriggersMustComeFromTheCatalogue() throws {
        let catalogue = TriggerCatalogue(triggers: [
            .init(id: "crowd", bg: "тълпа", en: "crowd")
        ])
        let journal = Journal(store: store, catalogue: catalogue)

        XCTAssertNoThrow(try journal.record(intensity: 2, triggers: ["crowd"]))
        XCTAssertThrowsError(try journal.record(intensity: 2, triggers: ["каквото се сетя"])) {
            XCTAssertEqual($0 as? JournalError, .unknownTrigger("каквото се сетя"))
        }
    }

    /// A missing data file must never cost someone their entry.
    func testRecordingWorksWithAnEmptyCatalogue() throws {
        let journal = Journal(store: store)
        XCTAssertNoThrow(try journal.record(intensity: 4, triggers: ["каквото и да е"]))
    }

    func testCatalogueLoadsFromDiskAndSurvivesAMissingFile() throws {
        let real = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("content/спусъци.json")
        XCTAssertFalse(TriggerCatalogue.load(from: real).triggers.isEmpty,
                       "истинският списък със спусъци трябва да се чете")

        let missing = folder.appendingPathComponent("нищо.json")
        XCTAssertTrue(TriggerCatalogue.load(from: missing).triggers.isEmpty)
    }

    // MARK: - Какво показва

    func testSummariesGroupByMonthNewestFirst() throws {
        let journal = Journal(store: store)
        try journal.record(intensity: 5, startedAt: date(2026, 3, 2))
        try journal.record(intensity: 3, startedAt: date(2026, 3, 20))
        try journal.record(intensity: 1, startedAt: date(2026, 4, 5))

        let summaries = try journal.summaries()
        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries[0].month, 4)
        XCTAssertEqual(summaries[0].count, 1)
        XCTAssertEqual(summaries[1].month, 3)
        XCTAssertEqual(summaries[1].count, 2)
        XCTAssertEqual(summaries[1].medianIntensity, 4)
    }

    /// Fewer episodes than last month is the only thing the journal reports as progress.
    func testTrendCountsEpisodesNotDays() throws {
        let journal = Journal(store: store)
        for day in 1...4 { try journal.record(intensity: 3, startedAt: date(2026, 3, day)) }
        try journal.record(intensity: 2, startedAt: date(2026, 4, 5))

        XCTAssertEqual(try journal.trend(), .fewer(by: 3))
    }

    func testTrendNeedsTwoMonths() throws {
        let journal = Journal(store: store)
        try journal.record(intensity: 2, startedAt: date(2026, 4, 5))
        XCTAssertEqual(try journal.trend(), .notEnoughHistory)
    }

    /// A month with nothing in it simply does not appear. It is not a broken streak and not
    /// a missed goal.
    func testAQuietMonthIsAbsentNotFailed() throws {
        let journal = Journal(store: store)
        try journal.record(intensity: 2, startedAt: date(2026, 1, 5))
        try journal.record(intensity: 2, startedAt: date(2026, 4, 5))

        let months = try journal.summaries().map(\.month)
        XCTAssertEqual(months, [4, 1])
    }

    // MARK: - Кога изобщо се предлага

    func testTheJournalIsOfferedOnlyAfterAnExerciseEnds() {
        XCTAssertTrue(JournalPrompt.shouldOffer(at: .exerciseFinished))
        XCTAssertFalse(JournalPrompt.shouldOffer(at: .duringExercise))
        XCTAssertFalse(JournalPrompt.shouldOffer(at: .appOpenedNormally))
        XCTAssertFalse(JournalPrompt.shouldOffer(at: .handedOverToHelp))
    }

    /// "Not now" is a real option: it records nothing and arranges nothing.
    func testSkippingLeavesNoTrace() throws {
        let journal = Journal(store: store)
        JournalPrompt.skip()
        XCTAssertTrue(try journal.episodes().isEmpty)
    }
}
