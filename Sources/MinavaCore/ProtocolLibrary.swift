import Foundation

/// Everything the app was able to load, and everything it refused, with reasons.
///
/// Loading never throws as a whole. One broken file must not take the exercise away from a
/// person — the app runs with what it has, and what it refused is visible to developers
/// rather than to them.
public struct ProtocolLibrary: Sendable {
    public struct Rejection: Sendable {
        public let file: String
        public let reason: String
    }

    public let plans: [ExecutablePlan]
    public let rejections: [Rejection]

    public var isEmpty: Bool { plans.isEmpty }

    /// True if anything loaded is unapproved. The interface must mark this unmistakably.
    public var containsProvisional: Bool { plans.contains { $0.isProvisional } }

    public func plan(id: String) -> ExecutablePlan? {
        plans.first { $0.protocolID == id }
    }

    /// Reads every `.json` file in a directory.
    ///
    /// A missing directory is not an error. `clinical/protocols/` is empty until a
    /// professional signs something off, and shipping without that part is the agreed
    /// behaviour — never shipping unapproved values "for now".
    public static func load(
        from directory: URL,
        build: BuildKind = .current
    ) -> ProtocolLibrary {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else {
            return ProtocolLibrary(plans: [], rejections: [])
        }

        var plans: [ExecutablePlan] = []
        var rejections: [Rejection] = []

        for name in names.sorted() where name.hasSuffix(".json") {
            let url = directory.appendingPathComponent(name)
            do {
                let file = try ClinicalProtocol.decoded(from: try Data(contentsOf: url))
                plans.append(try ExecutablePlan(file, build: build))
            } catch {
                rejections.append(Rejection(file: name, reason: Self.describe(error)))
            }
        }

        return ProtocolLibrary(plans: plans, rejections: rejections)
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case ProtocolGateError.unapprovedInRelease(let id, let version):
            return "\(id) версия \(version) няма писмено одобрение"
        case ProtocolGateError.notBreathing(let id):
            return "\(id) не описва дихателно упражнение"
        case ProtocolGateError.defect(let id, let defect):
            return "\(id): \(defect)"
        default:
            return String(describing: error)
        }
    }
}
