import Foundation

/// The words a person picks from when saying what set an episode off.
///
/// Chosen by tapping, never typed. Loaded from `content/спусъци.json` so the list can be
/// changed after clinical review without touching code.
public struct TriggerCatalogue: Sendable {
    public struct Trigger: Codable, Equatable, Sendable {
        public let id: String
        public let bg: String
        public let en: String?
    }

    public let triggers: [Trigger]

    public var identifiers: Set<String> { Set(triggers.map(\.id)) }

    public init(triggers: [Trigger]) {
        self.triggers = triggers
    }

    private struct File: Codable {
        let triggers: [Trigger]
    }

    /// A missing or broken catalogue leaves an empty one rather than throwing. Recording an
    /// episode must never fail because of a data file: the intensity alone is a valid entry.
    public static func load(from url: URL) -> TriggerCatalogue {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            return TriggerCatalogue(triggers: [])
        }
        return TriggerCatalogue(triggers: file.triggers)
    }
}

public enum JournalError: Error, Equatable, Sendable {
    case intensityOutOfRange(Int)
    case unknownTrigger(String)
}

/// Writing down an episode, and reading the record back.
///
/// Everything here is built around one number: **under thirty seconds**. That is why the only
/// required input is the intensity, why triggers are optional taps, and why nothing asks a
/// second question.
public struct Journal: Sendable {
    public static let intensityRange = 1...5

    private let store: EpisodeStoring
    private let catalogue: TriggerCatalogue

    public init(store: EpisodeStoring, catalogue: TriggerCatalogue = TriggerCatalogue(triggers: [])) {
        self.store = store
        self.catalogue = catalogue
    }

    /// One required input. Everything else has an answer already.
    @discardableResult
    public func record(
        intensity: Int,
        triggers: [String] = [],
        startedAt: Date = Date(),
        now: Date = Date()
    ) throws -> Episode {
        guard Journal.intensityRange.contains(intensity) else {
            throw JournalError.intensityOutOfRange(intensity)
        }
        if !catalogue.triggers.isEmpty {
            for trigger in triggers where !catalogue.identifiers.contains(trigger) {
                throw JournalError.unknownTrigger(trigger)
            }
        }

        let episode = Episode(startedAt: startedAt,
                              intensity: intensity,
                              triggers: triggers,
                              recordedAt: now)
        try store.save(episode)
        return episode
    }

    public func episodes() throws -> [Episode] {
        try store.all()
    }

    // MARK: - Какво показва дневникът

    /// Episodes in one month. Count and how strong they were — nothing else.
    public struct MonthlySummary: Equatable, Sendable {
        public let year: Int
        public let month: Int
        public let count: Int
        public let medianIntensity: Double?
    }

    /// Deliberately not a score, not a streak, not a percentage of anything.
    ///
    /// A month with no episodes reads as "no episodes", never as a broken streak or a lost
    /// achievement. A missed day for an anxious person is harm, not motivation.
    public func summaries(calendar: Calendar = Calendar(identifier: .gregorian)) throws -> [MonthlySummary] {
        var buckets: [String: (year: Int, month: Int, values: [Int])] = [:]

        for episode in try store.all() {
            let parts = calendar.dateComponents([.year, .month], from: episode.startedAt)
            guard let year = parts.year, let month = parts.month else { continue }
            let key = "\(year)-\(month)"
            var bucket = buckets[key] ?? (year, month, [])
            bucket.values.append(episode.intensity)
            buckets[key] = bucket
        }

        return buckets.values
            .map { MonthlySummary(year: $0.year,
                                  month: $0.month,
                                  count: $0.values.count,
                                  medianIntensity: Journal.median($0.values)) }
            .sorted { ($0.year, $0.month) > ($1.year, $1.month) }
    }

    /// Fewer episodes than the month before, more, or the same. That is the whole trend.
    public enum Trend: Equatable, Sendable {
        case fewer(by: Int)
        case more(by: Int)
        case same
        case notEnoughHistory
    }

    public func trend(calendar: Calendar = Calendar(identifier: .gregorian)) throws -> Trend {
        let summaries = try summaries(calendar: calendar)
        guard summaries.count >= 2 else { return .notEnoughHistory }
        let difference = summaries[0].count - summaries[1].count
        if difference < 0 { return .fewer(by: -difference) }
        if difference > 0 { return .more(by: difference) }
        return .same
    }

    static func median(_ values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return Double(sorted[middle]) }
        return Double(sorted[middle - 1] + sorted[middle]) / 2
    }
}

/// When the app is allowed to offer the journal.
///
/// Never during an episode, and never on its own initiative afterwards. The prompt exists in
/// exactly one moment: the exercise has ended and the person is still holding the phone.
/// Skipping is final — it schedules nothing and reminds no one.
public struct JournalPrompt: Equatable, Sendable {
    public enum Moment: Equatable, Sendable {
        case duringExercise
        case exerciseFinished
        case appOpenedNormally
        case handedOverToHelp
    }

    public static func shouldOffer(at moment: Moment) -> Bool {
        moment == .exerciseFinished
    }

    /// What happens when the person chooses "not now". Nothing does — and that is the point.
    public static func skip() -> Void {}
}
