import XCTest
@testable import MinavaCore

/// The real files in `clinical/personal/`, checked as files rather than as fixtures.
///
/// These practices are drafted from a book and nobody has approved them. The folder exists
/// so the author can use the app on their own phone; the tests here are what keeps that from
/// quietly becoming something other people receive.
final class PersonalPracticesTests: XCTestCase {

    private var folder: URL {
        Fixtures.repositoryRoot.appendingPathComponent("clinical/personal")
    }

    private func documents() throws -> [(name: String, file: ClinicalProtocol)] {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        return try names.sorted().filter { $0.hasSuffix(".json") }.map { name in
            let data = try Data(contentsOf: folder.appendingPathComponent(name))
            return (name, try ClinicalProtocol.decoded(from: data))
        }
    }

    // MARK: - Границата

    /// The guarantee, stated as a test: not one of these runs in a public build.
    func testNothingHereRunsInAReleaseBuild() throws {
        let library = ProtocolLibrary.load(from: folder, build: .release)

        XCTAssertTrue(library.isEmpty, "нито една практика оттук не влиза в публично издание")
        XCTAssertEqual(library.rejections.count, try documents().count)
        for rejection in library.rejections {
            XCTAssertTrue(rejection.reason.contains("одобрение"),
                          "причината трябва да е липсата на одобрение: \(rejection.reason)")
        }
    }

    func testNoFileHereClaimsApproval() throws {
        for (name, file) in try documents() {
            XCTAssertEqual(file.status, .draft, "\(name) не е чернова")
            XCTAssertNil(file.approval, "\(name) твърди одобрение, което не съществува")
            XCTAssertFalse(file.isExecutableInRelease, name)
        }
    }

    func testEverythingLoadsInAPersonalBuildAndIsMarkedProvisional() throws {
        let library = ProtocolLibrary.load(from: folder, build: .personal)

        XCTAssertTrue(library.rejections.isEmpty,
                      "нищо не бива да е счупено: \(library.rejections)")
        XCTAssertEqual(library.practices.count, try documents().count)
        XCTAssertTrue(library.containsProvisional)
        XCTAssertTrue(library.practices.allSatisfy(\.isProvisional))
    }

    // MARK: - Съдържанието

    func testIdentifiersAreUniqueAndMatchTheFileNames() throws {
        var seen: Set<String> = []
        for (name, file) in try documents() {
            XCTAssertEqual(name, "\(file.id).json")
            XCTAssertTrue(seen.insert(file.id).inserted, "повторен id: \(file.id)")
        }
    }

    func testEveryPracticeHasStepsAndBulgarianText() throws {
        for (name, file) in try documents() {
            XCTAssertNil(file.structuralDefect(), name)
            XCTAssertFalse(file.title.bg.isEmpty, name)
            XCTAssertFalse((file.steps ?? []).isEmpty, name)

            for step in (file.preparation ?? []) + (file.steps ?? []) {
                XCTAssertFalse(step.text.bg.isEmpty, name)
                // Read from a phone, sometimes with shaking hands. A step that needs three
                // lines is a step that gets skipped.
                XCTAssertLessThanOrEqual(step.text.bg.count, 100,
                                         "\(name): стъпката е твърде дълга за екран")
            }
        }
    }

    /// The rule from docs/ТРЕНИРАНЕ.md, checked against the files that actually exist: an
    /// exposure protocol must name a recovery practice, and that practice must be here.
    func testEveryExposureHasARecoveryPracticeThatExists() throws {
        let all = try documents()
        let known = Set(all.map(\.file.id))
        var exposures = 0

        for (name, file) in all where file.kind == .exposure {
            exposures += 1
            let recovery = try XCTUnwrap(file.recoveryProtocol, name)
            XCTAssertTrue(known.contains(recovery),
                          "\(name) сочи към \(recovery), а такава практика няма")
        }

        XCTAssertEqual(exposures, 1, "очаква се точно една експозиционна практика")
    }

    /// Load-time half of the same rule: if the recovery practice is missing from the folder,
    /// the exposure is not offered at all.
    func testAnExposureIsDroppedWhenItsRecoveryPracticeIsAbsent() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("minava-personal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let exposure = try XCTUnwrap(try documents().first { $0.file.kind == .exposure })
        try Data(contentsOf: folder.appendingPathComponent(exposure.name))
            .write(to: temporary.appendingPathComponent(exposure.name))

        let library = ProtocolLibrary.load(from: temporary, build: .personal)

        XCTAssertTrue(library.practices.isEmpty)
        XCTAssertEqual(library.rejections.count, 1)
        XCTAssertTrue(library.rejections[0].reason.contains("възстановяване"),
                      library.rejections[0].reason)
    }

    // MARK: - Какво личният билд не разхлабва

    /// A personal build forgives unapproved exercises. It does not forgive a phone number
    /// nobody has checked — the consequence of getting that wrong is of a different kind.
    func testAPersonalBuildStillHidesUnverifiedCrisisLines() {
        let unverified = CrisisLine(id: "line", name: "Линия", number: "0700 00 000",
                                    hours: "денонощно", languages: ["bg"], verifiedOn: nil)
        let directory = CrisisDirectory(lines: [unverified])

        XCTAssertEqual(directory.visible(build: .personal).map(\.number), ["112"])
        XCTAssertEqual(directory.visible(build: .debug).map(\.id), ["line"])
    }

    func testAPersonalBuildAllowsUnapprovedContentButReleaseDoesNot() {
        XCTAssertTrue(BuildKind.personal.allowsUnapprovedContent)
        XCTAssertTrue(BuildKind.debug.allowsUnapprovedContent)
        XCTAssertFalse(BuildKind.release.allowsUnapprovedContent)

        XCTAssertTrue(BuildKind.personal.requiresVerifiedCrisisLines)
        XCTAssertTrue(BuildKind.release.requiresVerifiedCrisisLines)
        XCTAssertFalse(BuildKind.debug.requiresVerifiedCrisisLines)
    }
}
