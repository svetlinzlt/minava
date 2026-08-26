import Foundation

/// Which kind of build is asking. A release build refuses unapproved clinical values.
public enum BuildKind: Sendable, Equatable {
    case debug
    case release

    public static var current: BuildKind {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }
}

public enum ProtocolGateError: Error, Equatable, Sendable {
    /// The file exists but does not describe a breathing exercise.
    case notBreathing(id: String)
    /// No one has signed this version off, and this is a release build. It does not run.
    case unapprovedInRelease(id: String, version: Int)
    /// The values are outside what the engine can execute at all.
    case defect(id: String, ProtocolDefect)
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
        if build == .release && !approved {
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
