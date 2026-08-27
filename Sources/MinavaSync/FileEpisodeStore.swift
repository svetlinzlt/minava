import Foundation

/// Deletes the copy that lives outside the device. Implemented by the app over CloudKit;
/// the store never knows which technology is behind it.
public protocol RemoteDeleting: Sendable {
    /// Returns `true` when the remote copy is gone. `false` means it is queued — usually
    /// because there is no network — and the screen must say so.
    func deleteEverything() -> Bool
}

/// A store backed by one JSON file.
///
/// Pure Foundation on purpose: it runs in tests on any machine, and it is the reference the
/// SwiftData implementation must agree with. Episodes are few — a person has tens of them a
/// year, not thousands — so a whole-file write is the right amount of machinery.
public final class FileEpisodeStore: EpisodeStoring, @unchecked Sendable {
    private let url: URL
    private let remote: RemoteDeleting?
    private let lock = NSLock()

    public init(url: URL, remote: RemoteDeleting? = nil) {
        self.url = url
        self.remote = remote
    }

    // MARK: - EpisodeStoring

    public func save(_ episode: Episode) throws {
        lock.lock()
        defer { lock.unlock() }

        var episodes = try readUnlocked()
        episodes.removeAll { $0.id == episode.id }
        episodes.append(episode)
        try writeUnlocked(episodes)
    }

    public func all() throws -> [Episode] {
        lock.lock()
        defer { lock.unlock() }
        // Newest first: the journal is read from today backwards.
        return try readUnlocked().sorted { $0.startedAt > $1.startedAt }
    }

    public func delete(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        var episodes = try readUnlocked()
        episodes.removeAll { $0.id == id }
        try writeUnlocked(episodes)
    }

    /// Local records go immediately. The remote copy may still be queued, and the caller is
    /// told which happened — never a cheerful "done" that is not true.
    public func deleteEverything() throws -> DeletionOutcome {
        lock.lock()
        defer { lock.unlock() }

        try writeUnlocked([])
        try? FileManager.default.removeItem(at: url)

        guard let remote else { return .complete }
        return remote.deleteEverything() ? .complete : .remotePending
    }

    public func export() throws -> Data {
        let episodes = try all()
        return try EpisodeExport(episodes: episodes).encoded()
    }

    // MARK: - Файлът

    private func readUnlocked() throws -> [Episode] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        return try decoder().decode([Episode].self, from: data)
    }

    private func writeUnlocked(_ episodes: [Episode]) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder().encode(episodes)
        // Atomic: a crash mid-write must not leave someone without their records.
        try data.write(to: url, options: .atomic)
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// The file a person receives when they export.
///
/// Plain, versioned and readable by a human as well as by a program. It exists so the records
/// can be taken to a professional, and so the app is not a trap: nobody should stay in Minava
/// because they cannot get their notes out.
public struct EpisodeExport: Codable, Equatable, Sendable {
    public let format: String
    public let version: Int
    public let exportedAt: Date
    public let episodes: [Episode]

    public init(episodes: [Episode], exportedAt: Date = Date()) {
        self.format = "minava-episodes"
        self.version = 1
        self.exportedAt = exportedAt
        self.episodes = episodes
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> EpisodeExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EpisodeExport.self, from: data)
    }

    /// The same records as plain text, one episode per line.
    ///
    /// JSON is correct and a program reads it, but a person who wants to show their journal
    /// to a professional opens an unreadable file. This is the version that can be printed,
    /// or read aloud in a room.
    ///
    /// Trigger labels are resolved through the catalogue so the file says "тълпа" rather
    /// than "crowd"; an unknown identifier falls back to itself instead of disappearing.
    public func plainText(catalogue: TriggerCatalogue = TriggerCatalogue(triggers: [])) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd HH:mm"

        var labels: [String: String] = [:]
        for trigger in catalogue.triggers { labels[trigger.id] = trigger.bg }

        var lines = ["Дневник на епизодите · Minava",
                     "Изнесено на " + day.string(from: exportedAt),
                     "Записи: \(episodes.count)",
                     ""]

        for episode in episodes.sorted(by: { $0.startedAt > $1.startedAt }) {
            var parts = [day.string(from: episode.startedAt), "сила \(episode.intensity)"]
            if !episode.triggers.isEmpty {
                parts.append(episode.triggers.map { labels[$0] ?? $0 }.joined(separator: ", "))
            }
            lines.append(parts.joined(separator: " · "))
        }

        if episodes.isEmpty { lines.append("(няма записи)") }
        return lines.joined(separator: "\n") + "\n"
    }
}
