import Foundation

/// One before-and-after rating of how activated the nervous system feels.
///
/// The loop it belongs to is described in docs/ТРЕНИРАНЕ.md: rate 0–10, notice where the
/// tension sits, do a practice, rate again. Without the second rating a person has no way of
/// seeing that anything worked.
public struct ActivationReading: Codable, Equatable, Sendable {
    public static let range = 0...10

    public let before: Int
    public let after: Int
    /// Which practice was run between the two ratings. Kept so the single reading means
    /// something; not kept as a tally of what has been run.
    public let protocolID: String
    public let recordedAt: Date

    public init(before: Int, after: Int, protocolID: String, recordedAt: Date = Date()) {
        self.before = before
        self.after = after
        self.protocolID = protocolID
        self.recordedAt = recordedAt
    }

    /// Negative means calmer. The only number the journal ever shows from this.
    public var change: Int { after - before }

    /// A reading from weeks ago should not be shown as if it were today's.
    public func isStale(on day: Date = Date(), after days: Int = 7) -> Bool {
        day.timeIntervalSince(recordedAt) > Double(days) * 86_400
    }
}

public enum ActivationError: Error, Equatable, Sendable {
    case outOfRange(Int)
}

/// Storage for **exactly one** reading.
///
/// This is deliberately not a collection. The decision behind it is recorded in
/// docs/ДАННИ.md: a sequence of readings is a history, a history becomes a chart, and a
/// chart becomes a streak. Keeping one value makes that impossible rather than forbidden —
/// there is no API here that could return a second one.
public protocol ActivationStoring: Sendable {
    func latest() throws -> ActivationReading?
    /// Replaces whatever was there. There is no append.
    func record(_ reading: ActivationReading) throws
    func clear() throws
}

/// Backed by one small file holding one object — not an array.
public final class FileActivationStore: ActivationStoring, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
    }

    public func latest() throws -> ActivationReading? {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ActivationReading.self, from: data)
    }

    public func record(_ reading: ActivationReading) throws {
        guard ActivationReading.range.contains(reading.before) else {
            throw ActivationError.outOfRange(reading.before)
        }
        guard ActivationReading.range.contains(reading.after) else {
            throw ActivationError.outOfRange(reading.after)
        }

        lock.lock()
        defer { lock.unlock() }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Whole-file write, so the previous reading cannot survive alongside the new one.
        try encoder.encode(reading).write(to: url, options: .atomic)
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }
}
