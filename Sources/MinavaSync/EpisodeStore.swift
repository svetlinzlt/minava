import Foundation
import MinavaCore

/// The only kind of record Minava keeps.
///
/// One flat value: when the episode started, how strong it was, and optionally what set it
/// off, chosen from a fixed list rather than typed. Completed exercises are deliberately not
/// stored — that is where streaks and percentages come from. See docs/ДАННИ.md.
public struct Episode: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    /// 1 to 5, chosen by tapping. A slider is unusable with shaking hands.
    public let intensity: Int
    public let triggers: [String]
    public let recordedAt: Date

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        intensity: Int,
        triggers: [String] = [],
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.startedAt = startedAt
        self.intensity = intensity
        self.triggers = triggers
        self.recordedAt = recordedAt
    }
}

/// What the app needs from storage, stated without naming a storage technology.
///
/// The SwiftData model and the CloudKit container live behind this protocol, so the rest of
/// the code never imports either. Deleting is one call and it is honest: local records go
/// immediately, and the caller is told whether the remote copy is still queued.
public protocol EpisodeStoring: Sendable {
    func save(_ episode: Episode) throws
    func all() throws -> [Episode]
    /// One record at a time — the right to correct is exercised without our help.
    func delete(id: UUID) throws
    func deleteEverything() throws -> DeletionOutcome
    func export() throws -> Data
}

public enum DeletionOutcome: Equatable, Sendable {
    /// Local and remote are both gone.
    case complete
    /// Local is gone; the remote deletion is waiting for a network. The screen says so
    /// rather than pretending it finished.
    case remotePending
}

// Задача 3.5 спира дотук — това е границата на модула, не реализацията ѝ.
// SwiftData моделът и CloudKit контейнерът идват с 4.4 и 4.6.
