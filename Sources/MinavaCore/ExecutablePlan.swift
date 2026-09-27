import Foundation

/// Which kind of build is asking. A release build refuses unapproved clinical values.
public enum BuildKind: Sendable, Equatable {
    case debug
    case release
    /// A build made for one named person, installed on their own phone.
    ///
    /// It exists so that "unapproved content never ships" can stay literally true while the
    /// author still uses the app themselves. Nothing here reaches another person: a personal
    /// build is not distributed, not on TestFlight, and not in the App Store. The rule in
    /// docs/ПЛАН.md is about publishing, and this case is the place where that
    /// distinction is written down instead of being remembered.
    case personal

    public static var current: BuildKind {
        #if MINAVA_PERSONAL
        return .personal
        #elseif DEBUG
        return .debug
        #else
        return .release
        #endif
    }

    /// Whether a protocol nobody has signed off on may run at all.
    ///
    /// True for development and for a personal build; false for release. When it is true the
    /// plan carries `isProvisional` and the interface is obliged to say so on screen.
    public var allowsUnapprovedContent: Bool {
        switch self {
        case .debug, .personal: return true
        case .release: return false
        }
    }

    /// Whether a crisis line must have been verified personally within the year to be shown.
    ///
    /// A personal build is strict here, unlike with clinical content. The reason is not
    /// symmetry but consequence: an unapproved exercise at worst does nothing, while a phone
    /// number that no longer answers fails a person at the exact moment they call it.
    public var requiresVerifiedCrisisLines: Bool {
        switch self {
        case .debug: return false
        case .personal, .release: return true
        }
    }
}

public enum ProtocolGateError: Error, Equatable, Sendable {
    /// The file exists but does not describe a breathing exercise.
    case notBreathing(id: String)
    /// The file exists but is not a step-based practice.
    case notAPractice(id: String)
    /// No one has signed this version off, and this is a release build. It does not run.
    case unapprovedInRelease(id: String, version: Int)
    /// The values are outside what the engine can execute at all.
    case defect(id: String, ProtocolDefect)
    /// The file does not make sense as a practice — no steps, an impossible round count,
    /// or an exposure protocol with no way back into regulation.
    case structural(id: String, StructuralDefect)
}

/// A breathing plan that has passed the gate and may be run.
///
/// This type is the only way to start a session, and its single initialiser is the only door
/// through the gate. That is the point: "the release build refuses unapproved values" is a
/// property of the type system here, not a check someone has to remember to call.
public struct ExecutablePlan: Equatable, Sendable {
    public let protocolID: String
    public let version: Int
    public let plan: BreathingPlan

    /// True only in a development build running something nobody has approved.
    ///
    /// When this is true the interface must carry a visible, non-dismissable marker. A
    /// screenshot of a development build must never be mistakable for the real thing.
    public let isProvisional: Bool

    public init(_ file: ClinicalProtocol, build: BuildKind = .current) throws {
        guard file.kind == .breathing, let plan = file.breathing else {
            throw ProtocolGateError.notBreathing(id: file.id)
        }

        do {
            try plan.checkMechanicalBounds()
        } catch let defect as ProtocolDefect {
            throw ProtocolGateError.defect(id: file.id, defect)
        }

        let approved = file.isExecutableInRelease
        if !approved && !build.allowsUnapprovedContent {
            throw ProtocolGateError.unapprovedInRelease(id: file.id, version: file.version)
        }

        self.protocolID = file.id
        self.version = file.version
        self.plan = plan
        self.isProvisional = !approved
    }

    public var totalDuration: TimeInterval { plan.totalDuration }

    public func timeline(tempo: Double = 1) -> [TimelineStep] {
        Timeline.steps(for: plan, tempo: tempo)
    }
}
