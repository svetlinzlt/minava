import Foundation

/// A clinical protocol file, as stored in `clinical/`.
///
/// The shape mirrors `clinical/schema/protocol.schema.json` exactly. The schema is the
/// contract; these types are one reader of it. Task 3.7 adds a test that the two agree,
/// so that a change to one cannot quietly diverge from the other.
///
/// Nothing here decides what is clinically correct. The values arrive as data and are
/// approved in writing, per version, by a qualified professional.
public struct ClinicalProtocol: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case breathing, grounding, exposure, screening, crisisPath = "crisis-path"
    }

    public enum Status: String, Codable, Sendable {
        case draft, review, approved
    }

    public let schemaVersion: Int
    public let id: String
    public let version: Int
    public let kind: Kind
    public let status: Status
    public let approval: Approval?
    public let title: LocalizedText
    public let excludedBy: String?
    public let breathing: BreathingPlan?
    public let steps: [GroundingStep]?
    public let notes: String?

    /// Whether a release build is allowed to execute this protocol.
    ///
    /// Approval is granted to one version of one file. Change a value, raise the version,
    /// and the old approval stops applying — which is the entire point of it.
    public var isExecutableInRelease: Bool {
        guard status == .approved, let approval else { return false }
        return approval.appliesToVersion == version
    }

    /// Reads one protocol file. Kept here so every caller decodes it the same way.
    public static func decoded(from data: Data) throws -> ClinicalProtocol {
        try JSONDecoder().decode(ClinicalProtocol.self, from: data)
    }
}

public struct Approval: Codable, Equatable, Sendable {
    public struct Person: Codable, Equatable, Sendable {
        public let name: String
        public let credentials: String
        public let registration: String?
    }

    public let approvedBy: Person
    public let approvedAt: String
    public let appliesToVersion: Int
    public let scope: String
    public let reviewDue: String?
}

public struct LocalizedText: Codable, Equatable, Sendable {
    public let bg: String
    public let en: String?
}

public struct GroundingStep: Codable, Equatable, Sendable {
    public let text: LocalizedText
    public let minDuration: Double?
}

/// The breathing exercise: an entry, a repeated cycle, and an exit that is never abrupt.
public struct BreathingPlan: Codable, Equatable, Sendable {
    public struct Phase: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable, CaseIterable {
            /// Fixed order. A cycle may omit either hold, never reorder.
            case inhale, holdIn, exhale, holdOut
        }

        public enum HapticIntensity: String, Codable, Sendable {
            case rising, falling, steady
        }

        public let type: Kind
        public let duration: TimeInterval
        public let hapticIntensity: HapticIntensity?

        public init(type: Kind, duration: TimeInterval, hapticIntensity: HapticIntensity?) {
            self.type = type
            self.duration = duration
            self.hapticIntensity = hapticIntensity
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public let duration: TimeInterval

        public init(duration: TimeInterval) {
            self.duration = duration
        }
    }

    public struct Cycle: Codable, Equatable, Sendable {
        public let phases: [Phase]

        public init(phases: [Phase]) {
            self.phases = phases
        }
    }

    public struct Repeat: Codable, Equatable, Sendable {
        public let cycles: Int
        public let firstCycleFactor: Double?

        public init(cycles: Int, firstCycleFactor: Double? = nil) {
            self.cycles = cycles
            self.firstCycleFactor = firstCycleFactor
        }
    }

    public struct Exit: Codable, Equatable, Sendable {
        public let duration: TimeInterval

        public init(duration: TimeInterval) {
            self.duration = duration
        }
    }

    public struct UserTempo: Codable, Equatable, Sendable {
        public let min: Double
        public let max: Double

        public init(min: Double, max: Double) {
            self.min = min
            self.max = max
        }
    }

    public let entry: Entry
    public let cycle: Cycle
    public let `repeat`: Repeat
    public let exit: Exit
    public let userTempo: UserTempo?

    // Публичен конструктор, защото тези типове се създават и извън модула — в
    // тестовете и в приложенията. Публична структура без публичен конструктор се
    // прави само чрез декодиране, което е дефект, а не решение.
    public init(
        entry: Entry,
        cycle: Cycle,
        repeat: Repeat,
        exit: Exit,
        userTempo: UserTempo? = nil
    ) {
        self.entry = entry
        self.cycle = cycle
        self.repeat = `repeat`
        self.exit = exit
        self.userTempo = userTempo
    }
}
