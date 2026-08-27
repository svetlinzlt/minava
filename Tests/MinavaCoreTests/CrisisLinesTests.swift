import XCTest
@testable import MinavaCore

final class CrisisLinesTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var parts = DateComponents()
        parts.year = year; parts.month = month; parts.day = dayOfMonth
        return calendar.date(from: parts)!
    }

    private func line(
        id: String,
        number: String,
        hours: String = "за проверка",
        verifiedOn: String? = nil
    ) -> CrisisLine {
        CrisisLine(id: id, name: id, number: number, hours: hours,
                   languages: ["bg"], verifiedOn: verifiedOn,
                   verifiedBy: verifiedOn == nil ? nil : "Тест")
    }

    // MARK: - Истинският регистър

    func testTheRealRegistryLoads() throws {
        let directory = CrisisDirectory.load(from: registryURL())
        XCTAssertFalse(directory.lines.isEmpty)
        XCTAssertEqual(directory.validDays, 365)
    }

    /// Днес нито един номер не е проверен лично. Този тест описва точно това състояние и
    /// ще се промени, когато задача 1.3 бъде свършена — нарочно.
    func testEveryRealLineIsStillUnverified() {
        let directory = CrisisDirectory.load(from: registryURL())
        XCTAssertEqual(directory.stale().count, directory.lines.count,
                       "ако някой номер е проверен, този тест трябва да се обнови")
    }

    /// Гейтът, върху истинските данни: релийз билд днес не би показал нищо освен 112.
    func testAReleaseBuildTodayWouldShowOnlyTheEmergencyNumber() {
        let directory = CrisisDirectory.load(from: registryURL())
        let visible = directory.visible(build: .release)

        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.number, "112")
    }

    func testADevelopmentBuildShowsEverythingSoTheScreenCanBeBuilt() {
        let directory = CrisisDirectory.load(from: registryURL())
        XCTAssertEqual(directory.visible(build: .debug).count, directory.lines.count)
    }

    // MARK: - Гейтът

    func testAVerifiedLineIsShownAndAStaleOneIsNot() {
        let directory = CrisisDirectory(lines: [
            line(id: "fresh", number: "0800 11 977", verifiedOn: "2026-06-01"),
            line(id: "stale", number: "0800 20 202", verifiedOn: "2024-01-01")
        ])

        let visible = directory.visible(on: day(2026, 8, 27), build: .release)
        XCTAssertEqual(visible.map(\.id), ["fresh"])
    }

    func testVerificationExpiresExactlyAfterAYear() {
        let directory = CrisisDirectory(lines: [
            line(id: "line", number: "0800 11 977", verifiedOn: "2025-08-27")
        ])
        XCTAssertEqual(directory.visible(on: day(2026, 8, 26), build: .release).first?.id, "line")
        XCTAssertEqual(directory.visible(on: day(2026, 8, 28), build: .release).first?.number,
                       "112", "след една година проверката отпада")
    }

    func testAFutureDateDoesNotCountAsVerified() {
        let directory = CrisisDirectory(lines: [
            line(id: "line", number: "0800 11 977", verifiedOn: "2030-01-01")
        ])
        XCTAssertEqual(directory.visible(on: day(2026, 8, 27), build: .release).first?.number, "112")
    }

    /// Празният екран е невъзможен: винаги остава поне 112.
    func testAnEmptyDirectoryStillOffersTheEmergencyNumber() {
        let visible = CrisisDirectory(lines: []).visible(build: .release)
        XCTAssertEqual(visible.map(\.number), ["112"])
    }

    func testAMissingFileStillOffersTheEmergencyNumber() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("няма-такъв-\(UUID().uuidString).json")
        XCTAssertEqual(CrisisDirectory.load(from: missing).visible(build: .release).map(\.number),
                       ["112"])
    }

    // MARK: - Подредбата и набирането

    func testEmergencyComesFirstThenRoundTheClockLines() {
        let directory = CrisisDirectory(lines: [
            line(id: "office", number: "02 492 30 30"),
            line(id: "always", number: "0800 11 977", hours: "денонощно"),
            line(id: "emergency", number: "112", hours: "денонощно")
        ])
        XCTAssertEqual(directory.visible(build: .debug).map(\.id),
                       ["emergency", "always", "office"])
    }

    /// Подредбата е една и съща всеки път. Човек трябва да намира едно и също на едно и
    /// също място, а не най-подходящото според нас.
    func testOrderIsStable() {
        let directory = CrisisDirectory.load(from: registryURL())
        XCTAssertEqual(directory.visible(build: .debug).map(\.id),
                       directory.visible(build: .debug).map(\.id))
    }

    func testOneTapDialsWithoutTheSpaces() {
        XCTAssertEqual(line(id: "l", number: "0800 11 977").dialURL?.absoluteString,
                       "tel:080011977")
        XCTAssertEqual(CrisisDirectory.emergency.dialURL?.absoluteString, "tel:112")
    }

    // MARK: - Помощ

    private func registryURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("content/кризисни-линии.json")
    }
}
