import XCTest
@testable import MinavaCore

final class ClinicalProtocolTests: XCTestCase {

    private let examplePath = "clinical/examples/example-breathing-acute.json"

    func testTheExampleFileDecodes() throws {
        let file = try ClinicalProtocol.decoded(from: Fixtures.data(at: examplePath))
        XCTAssertEqual(file.kind, .breathing)
        XCTAssertEqual(file.schemaVersion, 1)
        XCTAssertNotNil(file.breathing)
    }

    /// The one guarantee that matters: filler values cannot reach a release build.
    func testTheExampleFileIsNotExecutableInRelease() throws {
        let file = try ClinicalProtocol.decoded(from: Fixtures.data(at: examplePath))
        XCTAssertEqual(file.status, .draft)
        XCTAssertNil(file.approval)
        XCTAssertFalse(file.isExecutableInRelease)
    }

    func testApprovalForAnotherVersionDoesNotCount() throws {
        let approved = try approvedProtocol(version: 3, appliesToVersion: 3)
        XCTAssertTrue(approved.isExecutableInRelease)

        let stale = try approvedProtocol(version: 4, appliesToVersion: 3)
        XCTAssertFalse(stale.isExecutableInRelease,
                       "одобрението важи за една версия — вдигнеш ли я, то отпада")
    }

    func testTheExamplePlanPassesMechanicalBounds() throws {
        let file = try ClinicalProtocol.decoded(from: Fixtures.data(at: examplePath))
        let plan = try XCTUnwrap(file.breathing)
        XCTAssertNoThrow(try plan.checkMechanicalBounds())
    }

    /// The schema in `clinical/` is the contract; `MechanicalBounds` is one reader of it.
    /// If the two ever disagree, a file the validator accepts could be refused by the app,
    /// or the other way round — silently. This test makes that impossible.
    func testSwiftBoundsMatchTheSchema() throws {
        let schema = try Fixtures.json(at: "clinical/schema/protocol.schema.json")
        let breathing = try node(schema, "properties", "breathing", "properties")

        let phase = try node(breathing, "cycle", "properties", "phases")
        XCTAssertEqual(phase["minItems"] as? Int, MechanicalBounds.phasesPerCycle.lowerBound)
        XCTAssertEqual(phase["maxItems"] as? Int, MechanicalBounds.phasesPerCycle.upperBound)

        let duration = try node(phase, "items", "properties", "duration")
        XCTAssertEqual(number(duration["minimum"]), MechanicalBounds.phaseDuration.lowerBound)
        XCTAssertEqual(number(duration["maximum"]), MechanicalBounds.phaseDuration.upperBound)

        let entry = try node(breathing, "entry", "properties", "duration")
        XCTAssertEqual(number(entry["maximum"]), MechanicalBounds.entryDuration.upperBound)

        let exit = try node(breathing, "exit", "properties", "duration")
        XCTAssertEqual(number(exit["minimum"]), MechanicalBounds.exitDuration.lowerBound)
        XCTAssertEqual(number(exit["maximum"]), MechanicalBounds.exitDuration.upperBound)

        let cycles = try node(breathing, "repeat", "properties", "cycles")
        XCTAssertEqual(cycles["minimum"] as? Int, MechanicalBounds.cycles.lowerBound)
        XCTAssertEqual(cycles["maximum"] as? Int, MechanicalBounds.cycles.upperBound)

        let factor = try node(breathing, "repeat", "properties", "firstCycleFactor")
        XCTAssertEqual(number(factor["minimum"]),
                       MechanicalBounds.firstCycleFactor.lowerBound)
        XCTAssertEqual(number(factor["maximum"]),
                       MechanicalBounds.firstCycleFactor.upperBound)
    }

    /// `clinical/protocols/` holds only what a professional has signed off on. An empty
    /// folder is a correct state; an unapproved file in it is not.
    func testNothingUnapprovedSitsInTheProtocolsFolder() throws {
        let folder = Fixtures.repositoryRoot.appendingPathComponent("clinical/protocols")
        let files = try FileManager.default
            .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        for url in files {
            let file = try ClinicalProtocol.decoded(from: try Data(contentsOf: url))
            XCTAssertTrue(file.isExecutableInRelease,
                          "\(url.lastPathComponent) стои при одобрените, но не е одобрен")
        }
    }

    // MARK: - Helpers

    private func approvedProtocol(version: Int, appliesToVersion: Int) throws -> ClinicalProtocol {
        var object = try Fixtures.json(at: examplePath)
        object["version"] = version
        object["status"] = "approved"
        object["approval"] = [
            "approvedBy": ["name": "Тест Тестов", "credentials": "клиничен психолог"],
            "approvedAt": "2026-09-01",
            "appliesToVersion": appliesToVersion,
            "scope": "остър епизод при паническо разстройство"
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try ClinicalProtocol.decoded(from: data)
    }

    private func node(_ object: [String: Any], _ keys: String...) throws -> [String: Any] {
        var current = object
        for key in keys {
            current = try XCTUnwrap(current[key] as? [String: Any], "липсва \(key)")
        }
        return current
    }

    private func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}

extension ClinicalProtocolTests {

    /// Същият принцип като при границите: схемата е договорът, а Swift е един неин
    /// четец. Разминат ли се стойностите за дълбочина, файл, приет от валидатора, би
    /// бил отказан от приложението — мълчаливо.
    func testDepthValuesMatchTheSchema() throws {
        let schema = try Fixtures.json(at: "clinical/schema/protocol.schema.json")
        let phase = try node(schema, "properties", "breathing", "properties",
                             "cycle", "properties", "phases", "items", "properties")
        let depth = try node(phase, "depth")
        let inSchema = Set(try XCTUnwrap(depth["enum"] as? [String]))

        XCTAssertEqual(inSchema, ["shallow", "normal", "deep"])
        for value in inSchema {
            XCTAssertNotNil(BreathingPlan.Phase.Depth(rawValue: value),
                            "схемата допуска \(value), а Swift не го познава")
        }
    }
}
