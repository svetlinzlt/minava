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

    public init(store: EpisodeStoring, preferences: PreferencesStoring) {
        self.store = store
        self.preferences = preferences
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
        try store.export()
    }

    /// A name with a date in it, so a file in someone's downloads folder still makes sense
    /// in a year.
    public func exportFileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "minava-\(formatter.string(from: now)).json"
    }

    // MARK: - Изтриване

    /// One action, no confirmation typed out, no three screens.
    ///
    /// The result is passed on exactly as it comes: `.remotePending` must be shown as
    /// "the copy in iCloud is waiting for a network", never rounded up to done.
    public func deleteEverything() throws -> DeletionOutcome {
        try store.deleteEverything()
    }
}
