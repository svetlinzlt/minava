import Foundation

/// A step-based practice that has passed the gate and may be run.
///
/// The companion of `ExecutablePlan`. Breathing is driven by a clock and needs a timeline;
/// a practice is driven by the person moving from one step to the next, and the engine only
/// counts rounds and sides. Two types rather than one because the two are genuinely
/// different things to execute — and because a practice must never be startable through the
/// breathing door, nor the reverse.
///
/// The same rule applies through the same single initialiser: in a release build an
/// unapproved file does not become a value of this type at all.
public struct ExecutablePractice: Equatable, Sendable {
    public let protocolID: String
    public let version: Int
    public let kind: ClinicalProtocol.Kind
    /// Which group of the catalogue it appears under. Never nil for a practice that ran the
    /// gate — `structuralDefect()` refuses a practice without one.
    public let section: ClinicalProtocol.Section
    public let title: LocalizedText
    /// Roughly how long it takes, shown next to the name.
    public let estimatedMinutes: Int?
    /// What to do if it makes things worse. Always present for `.attention`.
    public let stopRule: LocalizedText?
    public let steps: [GroundingStep]
    /// Shown once, before the first round. Never repeated.
    public let preparation: [GroundingStep]

    /// How many times the whole sequence of steps repeats. One by default.
    public let rounds: Int
    /// Sides the practice is performed on, in order. Empty when it has no sides.
    public let sides: [ClinicalProtocol.Side]
    /// Present when the person is asked to rate before and after.
    public let measure: ClinicalProtocol.Measure?
    /// The regulation practice that must follow. Always present for an exposure protocol —
    /// `structuralDefect()` refuses the file otherwise.
    public let recoveryProtocol: String?

    /// True only when running something nobody has approved. The interface must say so.
    public let isProvisional: Bool

    public init(_ file: ClinicalProtocol, build: BuildKind = .current) throws {
        switch file.kind {
        case .grounding, .regulation, .exposure:
            break
        case .breathing, .screening, .crisisPath:
            throw ProtocolGateError.notAPractice(id: file.id)
        }

        if let defect = file.structuralDefect() {
            throw ProtocolGateError.structural(id: file.id, defect)
        }

        let approved = file.isExecutableInRelease
        if !approved && !build.allowsUnapprovedContent {
            throw ProtocolGateError.unapprovedInRelease(id: file.id, version: file.version)
        }

        self.protocolID = file.id
        self.version = file.version
        self.kind = file.kind
        // Safe: a practice without a section is a structural defect and was refused above.
        self.section = file.section ?? .nervousSystem
        self.title = file.title
        self.estimatedMinutes = file.estimatedMinutes
        self.stopRule = file.stopRule
        self.steps = file.steps ?? []
        self.preparation = file.preparation ?? []
        self.rounds = file.rounds ?? 1
        self.sides = file.sides ?? []
        self.measure = file.measure
        self.recoveryProtocol = file.recoveryProtocol
        self.isProvisional = !approved
    }

    /// Every step the person will be shown, in order, already expanded over sides and rounds.
    ///
    /// Expanded rather than nested so the interface has one flat list to walk and cannot get
    /// the order wrong. A practice with two sides and three rounds shows its steps six times
    /// — and its preparation exactly once, at the front.
    public var sequence: [Step] {
        var result: [Step] = preparation.map {
            Step(text: $0.text, minDuration: $0.minDuration, round: 0, side: nil)
        }
        let sidesToRun: [ClinicalProtocol.Side?] =
            sides.isEmpty ? [nil] : sides.map { Optional($0) }

        for round in 1...max(rounds, 1) {
            for side in sidesToRun {
                for step in steps {
                    result.append(Step(text: step.text,
                                       minDuration: step.minDuration,
                                       round: round,
                                       side: side))
                }
            }
        }
        return result
    }

    public struct Step: Equatable, Sendable {
        public let text: LocalizedText
        public let minDuration: TimeInterval?
        /// 1-based for the rounds themselves; `0` marks a preparation step, which belongs to
        /// no round and must never be counted as one.
        public let round: Int
        public let side: ClinicalProtocol.Side?
    }

    /// The shortest the practice can take, when every step is held for its minimum.
    ///
    /// A lower bound, not a promise: steps without a minimum contribute nothing, and nobody
    /// is hurried through the ones that have one.
    public var shortestDuration: TimeInterval {
        sequence.reduce(0) { $0 + ($1.minDuration ?? 0) }
    }
}
