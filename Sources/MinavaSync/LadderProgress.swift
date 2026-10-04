import Foundation

/// Where a person has got to on one ladder.
///
/// A ladder is a situation from `content/спусъци.json` with rungs ordered from the easiest
/// to the hardest. Climbing it takes days, so the app has to remember one thing: which
/// ladder, and which rung.
///
/// It remembers **exactly one**, and that is the whole design. Progress on several ladders
/// at once would be a collection, a collection becomes a history, and a history becomes the
/// chart that docs/ДАННИ.md exists to prevent. One ladder at a time is also how the thing is
/// meant to be done — so the constraint costs nothing clinically and buys the rule.
public struct LadderProgress: Codable, Equatable, Sendable {
    /// Which ladder. Switching to another one replaces this; there is no second slot.
    public let protocolID: String
    /// 0-based index of the rung the person is **on**, not the one they finished.
    public let rung: Int
    public let updatedAt: Date

    public init(protocolID: String, rung: Int, updatedAt: Date = Date()) {
        self.protocolID = protocolID
        self.rung = rung
        self.updatedAt = updatedAt
    }

    /// A ladder nobody has touched for a month is not where that person is any more.
    public func isStale(on day: Date = Date(), after days: Int = 30) -> Bool {
        day.timeIntervalSince(updatedAt) > Double(days) * 86_400
    }
}

public enum LadderError: Error, Equatable, Sendable {
    case rungOutOfRange(Int)
}

/// Storage for **one** ladder's progress. Deliberately not a collection.
public protocol LadderStoring: Sendable {
    func current() throws -> LadderProgress?
    /// Replaces whatever was there, including progress on a different ladder.
    func record(_ progress: LadderProgress, rungCount: Int) throws
    func clear() throws
}

/// Backed by one small file holding one object — not an array.
public final class FileLadderStore: LadderStoring, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
    }

    public func current() throws -> LadderProgress? {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LadderProgress.self, from: data)
    }

    public func record(_ progress: LadderProgress, rungCount: Int) throws {
        guard progress.rung >= 0, progress.rung < max(rungCount, 1) else {
            throw LadderError.rungOutOfRange(progress.rung)
        }

        lock.lock()
        defer { lock.unlock() }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Whole-file write: the previous ladder cannot survive alongside the new one.
        try encoder.encode(progress).write(to: url, options: .atomic)
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }
}
