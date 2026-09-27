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

    /// Breathing protocols, ready to run.
    public let plans: [ExecutablePlan]
    /// Step-based practices: grounding, regulation, exposure.
    public let practices: [ExecutablePractice]
    public let rejections: [Rejection]

    public var isEmpty: Bool { plans.isEmpty && practices.isEmpty }

    /// True if anything loaded is unapproved. The interface must mark this unmistakably.
    public var containsProvisional: Bool {
        plans.contains { $0.isProvisional } || practices.contains { $0.isProvisional }
    }

    public func plan(id: String) -> ExecutablePlan? {
        plans.first { $0.protocolID == id }
    }

    public func practice(id: String) -> ExecutablePractice? {
        practices.first { $0.protocolID == id }
    }

    /// The practices meant to be run between episodes rather than during one.
    public var regulation: [ExecutablePractice] {
        practices.filter { $0.kind == .regulation }
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
            return ProtocolLibrary(plans: [], practices: [], rejections: [])
        }

        var plans: [ExecutablePlan] = []
        var practices: [ExecutablePractice] = []
        var rejections: [Rejection] = []

        for name in names.sorted() where name.hasSuffix(".json") {
            let url = directory.appendingPathComponent(name)
            do {
                let file = try ClinicalProtocol.decoded(from: try Data(contentsOf: url))
                switch file.kind {
                case .breathing:
                    plans.append(try ExecutablePlan(file, build: build))
                case .grounding, .regulation, .exposure:
                    practices.append(try ExecutablePractice(file, build: build))
                case .screening, .crisisPath:
                    // Neither engine runs these: a screening file is a set of questions asked
                    // before a protocol, and a crisis path is a route through the interface.
                    // They are skipped rather than rejected — a rejection means something is
                    // wrong, and nothing is wrong with a file this loader does not own.
                    continue
                }
            } catch {
                rejections.append(Rejection(file: name, reason: Self.describe(error)))
            }
        }

        // An exposure protocol whose recovery practice is not here would leave a person in a
        // deliberately raised state with nothing to come back through. Refusing it is the
        // load-time half of the rule that `structuralDefect()` enforces inside one file.
        let available = Set(practices.map(\.protocolID))
        var kept: [ExecutablePractice] = []
        for practice in practices {
            if practice.kind == .exposure,
               let recovery = practice.recoveryProtocol,
               !available.contains(recovery) {
                rejections.append(Rejection(
                    file: "\(practice.protocolID).json",
                    reason: "\(practice.protocolID): практиката за възстановяване "
                          + "\(recovery) липсва"))
                continue
            }
            kept.append(practice)
        }

        return ProtocolLibrary(plans: plans, practices: kept, rejections: rejections)
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case ProtocolGateError.unapprovedInRelease(let id, let version):
            return "\(id) версия \(version) няма писмено одобрение"
        case ProtocolGateError.notBreathing(let id):
            return "\(id) не описва дихателно упражнение"
        case ProtocolGateError.notAPractice(let id):
            return "\(id) не описва практика със стъпки"
        case ProtocolGateError.defect(let id, let defect):
            return "\(id): \(defect)"
        case ProtocolGateError.structural(let id, let defect):
            return "\(id): \(defect)"
        default:
            return String(describing: error)
        }
    }
}
