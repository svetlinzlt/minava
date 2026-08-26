import XCTest
@testable import MinavaCore

final class ProtocolLibraryTests: XCTestCase {

    private var examples: URL {
        Fixtures.repositoryRoot.appendingPathComponent("clinical/examples")
    }

    private var approvedFolder: URL {
        Fixtures.repositoryRoot.appendingPathComponent("clinical/protocols")
    }

    func testExamplesLoadInADevelopmentBuildAndAreMarked() {
        let library = ProtocolLibrary.load(from: examples, build: .debug)

        XCTAssertFalse(library.isEmpty, "примерните файлове трябва да се четат")
        XCTAssertTrue(library.containsProvisional)
        XCTAssertTrue(library.rejections.isEmpty,
                      "нищо в examples/ не бива да е счупено: \(library.rejections)")
    }

    /// The whole point of the gate, on real files.
    func testExamplesAreAllRefusedInAReleaseBuild() {
        let library = ProtocolLibrary.load(from: examples, build: .release)

        XCTAssertTrue(library.isEmpty)
        XCTAssertEqual(library.rejections.count, 1)
        XCTAssertTrue(library.rejections[0].reason.contains("одобрение"),
                      "причината трябва да казва защо: \(library.rejections)")
    }

    /// An empty folder is the correct state today, and shipping without that part is the
    /// agreed behaviour. Loading must not throw or crash because of it.
    func testAnEmptyApprovedFolderIsNotAnError() {
        let library = ProtocolLibrary.load(from: approvedFolder, build: .release)
        XCTAssertTrue(library.isEmpty)
        XCTAssertTrue(library.rejections.isEmpty)
        XCTAssertFalse(library.containsProvisional)
    }

    func testAMissingFolderIsNotAnError() {
        let missing = Fixtures.repositoryRoot.appendingPathComponent("clinical/nowhere")
        let library = ProtocolLibrary.load(from: missing, build: .release)
        XCTAssertTrue(library.isEmpty)
        XCTAssertTrue(library.rejections.isEmpty)
    }

    /// One broken file must not take the exercise away from everyone.
    func testABrokenFileIsRejectedWithoutLosingTheRest() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("minava-library-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try Data("{ not json".utf8)
            .write(to: folder.appendingPathComponent("broken.json"))
        try Fixtures.data(at: "clinical/examples/example-breathing-acute.json")
            .write(to: folder.appendingPathComponent("good.json"))

        let library = ProtocolLibrary.load(from: folder, build: .debug)

        XCTAssertEqual(library.plans.count, 1)
        XCTAssertEqual(library.rejections.count, 1)
        XCTAssertEqual(library.rejections[0].file, "broken.json")
    }

    func testPlansCanBeFoundByIdentifier() {
        let library = ProtocolLibrary.load(from: examples, build: .debug)
        XCTAssertNotNil(library.plan(id: "example-breathing-acute"))
        XCTAssertNil(library.plan(id: "нещо-което-го-няма"))
    }
}
