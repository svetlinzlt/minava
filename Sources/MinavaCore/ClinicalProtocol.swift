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
        case breathing, grounding, exposure, screening
        /// Short practices run between episodes, not during one. They are the substance of
        /// the training mode described in docs/ТРЕНИРАНЕ.md.
        case regulation
        case crisisPath = "crisis-path"
    }

    /// What the person rates before and after, when the protocol is meant to be run as a
    /// loop rather than as a one-off exercise.
    public enum Measure: String, Codable, Sendable {
        case activation = "activation-0-10"
    }

    public enum Side: String, Codable, Sendable {
        case right, left
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
    /// Shown once before the rounds begin, and never repeated.
    ///
    /// Getting into position is not part of the exercise. A practice with nine rounds must
    /// not tell someone nine times where to put their hands.
    public let preparation: [GroundingStep]?
    /// Present when the protocol asks for a rating before and after.
    public let measure: Measure?
    /// How many times the whole sequence of `steps` repeats. A round is one pass through
    /// the steps, not one breath.
    public let rounds: Int?
    /// Sides the exercise is performed on, in order.
    public let sides: [Side]?
    /// The regulation protocol that must follow this one.
    ///
    /// Required for `.exposure`. Challenging without a way back into regulation accumulates
    /// tension, and where the nervous system is already dysregulated it can make symptoms
    /// worse — so an exposure protocol without one is refused rather than run.
    public let recoveryProtocol: String?
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

    public init(
        schemaVersion: Int = 1,
        id: String,
        version: Int,
        kind: Kind,
        status: Status,
        approval: Approval?,
        title: LocalizedText,
        excludedBy: String? = nil,
        breathing: BreathingPlan? = nil,
        steps: [GroundingStep]? = nil,
        preparation: [GroundingStep]? = nil,
        measure: Measure? = nil,
        rounds: Int? = nil,
        sides: [Side]? = nil,
        recoveryProtocol: String? = nil,
        notes: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.version = version
        self.kind = kind
        self.status = status
        self.approval = approval
        self.title = title
        self.excludedBy = excludedBy
        self.breathing = breathing
        self.steps = steps
        self.preparation = preparation
        self.measure = measure
        self.rounds = rounds
        self.sides = sides
        self.recoveryProtocol = recoveryProtocol
        self.notes = notes
    }

    /// Whether this file is internally consistent, beyond what the schema can express.
    ///
    /// Kept separate from `isExecutableInRelease`: approval is about who signed it, this is
    /// about whether it makes sense at all.
    public func structuralDefect() -> StructuralDefect? {
        switch kind {
        case .breathing where breathing == nil:
            return .missingBreathingPlan
        case .grounding, .regulation:
            if (steps ?? []).isEmpty { return .missingSteps }
        case .exposure:
            if recoveryProtocol == nil { return .exposureWithoutRecovery }
            if (steps ?? []).isEmpty { return .missingSteps }
        default:
            break
        }
        if let rounds, rounds < 1 { return .roundsOutOfBounds(rounds) }
        if let sides, Set(sides).count != sides.count { return .repeatedSide }
        return nil
    }
}

public enum StructuralDefect: Error, Equatable, Sendable {
    case missingBreathingPlan
    case missingSteps
    /// The rule from docs/ТРЕНИРАНЕ.md, made impossible to forget.
    case exposureWithoutRecovery
    case roundsOutOfBounds(Int)
    case repeatedSide
}

public struct Approval: Codable, Equatable, Sendable {
    public struct Person: Codable, Equatable, Sendable {
        public let name: String
        public let credentials: String
        public let registration: String?

        public init(name: String, credentials: String, registration: String? = nil) {
            self.name = name
            self.credentials = credentials
            self.registration = registration
        }
    }

    public let approvedBy: Person
    public let approvedAt: String
    public let appliesToVersion: Int
    public let scope: String
    public let reviewDue: String?

    public init(
        approvedBy: Person,
        approvedAt: String,
        appliesToVersion: Int,
        scope: String,
        reviewDue: String? = nil
    ) {
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.appliesToVersion = appliesToVersion
        self.scope = scope
        self.reviewDue = reviewDue
    }
}

public struct LocalizedText: Codable, Equatable, Sendable {
    public let bg: String
    public let en: String?

    public init(bg: String, en: String? = nil) {
        self.bg = bg
        self.en = en
    }
}

public struct GroundingStep: Codable, Equatable, Sendable {
    public let text: LocalizedText
    public let minDuration: Double?

    public init(text: LocalizedText, minDuration: Double? = nil) {
        self.text = text
        self.minDuration = minDuration
    }
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

        /// How full the breath is, separate from how long it lasts.
        ///
        /// The two are not the same instruction and the difference matters: telling someone
        /// to breathe slowly often makes them breathe *deeper*, because the feeling of
        /// suffocation invites a bigger breath. A deeper breath lowers CO₂, which is thought
        /// to be one of the mechanisms that sustains panic — the opposite of the intent.
        ///
        /// Which value belongs here is a clinical decision (task 6.1). The engine only
        /// carries it to the interface; it has no opinion.
        public enum Depth: String, Codable, Sendable {
            case shallow, normal, deep
        }

        public let type: Kind
        public let duration: TimeInterval
        public let hapticIntensity: HapticIntensity?
        public let depth: Depth?

        public init(
            type: Kind,
            duration: TimeInterval,
            hapticIntensity: HapticIntensity? = nil,
            depth: Depth? = nil
        ) {
            self.type = type
            self.duration = duration
            self.hapticIntensity = hapticIntensity
            self.depth = depth
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
