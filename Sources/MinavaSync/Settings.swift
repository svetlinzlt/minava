import Foundation

/// The few things a person may change.
///
/// Short on purpose. Every setting is a decision someone has to make, and this app asks a
/// person in a bad moment for as little as possible. There is no theme switch — the system
/// setting decides — and no haptic strength slider, because the system already has one.
public struct Preferences: Codable, Equatable, Sendable {
    /// The voice is an addition. Turning it off never removes information.
    public var voiceEnabled: Bool
    /// Off means everything stays on this device. Turning it off never deletes anything.
    public var syncEnabled: Bool

    public init(voiceEnabled: Bool = true, syncEnabled: Bool = true) {
        self.voiceEnabled = voiceEnabled
        self.syncEnabled = syncEnabled
    }
}

public protocol PreferencesStoring: Sendable {
    func load() -> Preferences
    func save(_ preferences: Preferences)
}

/// For tests and for a first run before anything has been written.
public final class InMemoryPreferences: PreferencesStoring, @unchecked Sendable {
    private var current: Preferences
    private let lock = NSLock()

    public init(_ preferences: Preferences = Preferences()) {
        self.current = preferences
    }

    public func load() -> Preferences {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    public func save(_ preferences: Preferences) {
        lock.lock(); defer { lock.unlock() }
        current = preferences
    }
}

/// The three things the settings screen actually does.
///
/// Kept away from the interface so each one can be tested for the property that matters:
/// export produces a readable file, deletion tells the truth, and turning sync off does not
/// cost anyone their records.
public struct SettingsService: Sendable {
    private let store: EpisodeStoring
    private let preferences: PreferencesStoring
    private let catalogue: TriggerCatalogue
    private let activation: ActivationStoring?
    private let ladder: LadderStoring?

    public init(
        store: EpisodeStoring,
        preferences: PreferencesStoring,
        catalogue: TriggerCatalogue = TriggerCatalogue(triggers: []),
        activation: ActivationStoring? = nil,
        ladder: LadderStoring? = nil
    ) {
        self.store = store
        self.preferences = preferences
        self.catalogue = catalogue
        self.activation = activation
        self.ladder = ladder
    }

    public var current: Preferences { preferences.load() }

    // MARK: - Синхронът

    /// Turning sync off leaves every local record in place. Nobody loses their journal by
    /// changing their mind about iCloud.
    public func setSync(enabled: Bool) {
        var updated = preferences.load()
        updated.syncEnabled = enabled
        preferences.save(updated)
    }

    public func setVoice(enabled: Bool) {
        var updated = preferences.load()
        updated.voiceEnabled = enabled
        preferences.save(updated)
    }

    // MARK: - Износ

    public func export() throws -> Data {
        try currentExport().encoded()
    }

    /// The readable version, for taking to a professional.
    public func exportText() throws -> String {
        try currentExport().plainText(catalogue: catalogue)
    }

    private func currentExport() throws -> EpisodeExport {
        EpisodeExport(episodes: try store.all(),
                      activation: try activation?.latest())
    }

    // MARK: - Скалата

    /// The single reading, if one has been taken. Never a list.
    /// Where the person is on their one ladder, if they have started one.
    public func currentLadder() throws -> LadderProgress? {
        try ladder?.current()
    }

    /// Moves the ladder. Starting a different one replaces the old progress — there is no
    /// second slot, and that is deliberate.
    public func recordLadder(protocolID: String, rung: Int, rungCount: Int,
                             now: Date = Date()) throws {
        try ladder?.record(LadderProgress(protocolID: protocolID, rung: rung,
                                          updatedAt: now),
                           rungCount: rungCount)
    }

    public func latestActivation() throws -> ActivationReading? {
        try activation?.latest()
    }

    /// Replaces the previous reading. There is no history to append to, by design.
    public func recordActivation(
        before: Int,
        after: Int,
        protocolID: String,
        now: Date = Date()
    ) throws {
        try activation?.record(ActivationReading(before: before,
                                                 after: after,
                                                 protocolID: protocolID,
                                                 recordedAt: now))
    }

    /// A name with a date in it, so a file in someone's downloads folder still makes sense
    /// in a year.
    public func exportFileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "minava-\(formatter.string(from: now)).json"
    }

    public func exportTextFileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "minava-\(formatter.string(from: now)).txt"
    }

    // MARK: - Изтриване

    /// One action, no confirmation typed out, no three screens.
    ///
    /// The result is passed on exactly as it comes: `.remotePending` must be shown as
    /// "the copy in iCloud is waiting for a network", never rounded up to done.
    public func deleteEverything() throws -> DeletionOutcome {
        // The ladder goes with it. "Everything" has to mean everything, or
        try ladder?.clear()
        // The single activation reading goes too. "Everything" has to mean everything, or
        // the word is a lie on a screen someone is trusting.
        try activation?.clear()
        return try store.deleteEverything()
    }
}
