import Foundation

/// One crisis line, as recorded in `content/кризисни-линии.json`.
///
/// `verifiedOn` is the date somebody **called the number** and heard a person. It is not the
/// date somebody found it on a website. A wrong crisis number is worse than a missing one:
/// a person who dials and reaches a dead line loses the attempt that cost them the most.
public struct CrisisLine: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let number: String
    public let hours: String
    public let languages: [String]
    public let verifiedOn: String?
    public let verifiedBy: String?
    /// `nil` means nobody has checked — never assume it is free. A person without
    /// credit has to know the cost *before* dialling, not after.
    public let isFreeCall: Bool?
    public let notes: String?

    public init(
        id: String,
        name: String,
        number: String,
        hours: String,
        languages: [String],
        verifiedOn: String? = nil,
        verifiedBy: String? = nil,
        isFreeCall: Bool? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.number = number
        self.hours = hours
        self.languages = languages
        self.verifiedOn = verifiedOn
        self.verifiedBy = verifiedBy
        self.isFreeCall = isFreeCall
        self.notes = notes
    }

    /// What the screen says about the cost, in three honest states.
    public enum CallCost: Equatable, Sendable {
        case free
        case charged
        /// Nobody checked. The screen says so rather than staying silent, because
        /// silence reads as "free".
        case unknown
    }

    public var callCost: CallCost {
        switch isFreeCall {
        case .some(true): return .free
        case .some(false): return .charged
        case .none: return .unknown
        }
    }

    /// What a single tap opens. Spaces are for reading, not for dialling.
    public var dialURL: URL? {
        let digits = number.filter { !$0.isWhitespace }
        return URL(string: "tel:\(digits)")
    }

    public func isCurrent(on day: Date, validDays: Int, calendar: Calendar) -> Bool {
        guard let verified = CrisisDirectory.date(from: verifiedOn) else { return false }
        let days = calendar.dateComponents([.day], from: verified, to: day).day ?? .max
        return days >= 0 && days <= validDays
    }
}

/// The screen behind the word "Помощ".
///
/// Loads from a bundled file and touches nothing else. No network, no lookup, no freshness
/// check against a server — the panic path has no step that can fail, and this is part of it.
public struct CrisisDirectory: Sendable {
    /// The one number that is not read from the file.
    ///
    /// 112 is the statutory emergency number across the EU. It exists here as a constant so
    /// that a person opening the crisis screen always sees something, even if every entry in
    /// the registry has gone stale. This is the single hardcoded number in the project and
    /// the reason is written down so nobody adds a second one.
    public static let emergency = CrisisLine(
        id: "emergency-112",
        name: "Спешни повиквания",
        number: "112",
        hours: "денонощно",
        languages: ["bg", "en"],
        isFreeCall: true)

    public let lines: [CrisisLine]
    public let validDays: Int

    public init(lines: [CrisisLine], validDays: Int = 365) {
        self.lines = lines
        self.validDays = validDays
    }

    private struct File: Codable {
        let verificationValidDays: Int?
        let lines: [CrisisLine]
    }

    /// A missing or broken file leaves a directory with 112 in it rather than an empty screen.
    public static func load(from url: URL) -> CrisisDirectory {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            return CrisisDirectory(lines: [])
        }
        return CrisisDirectory(lines: file.lines,
                               validDays: file.verificationValidDays ?? 365)
    }

    /// What the screen shows.
    ///
    /// In a release build only lines verified within the last year are offered. Everything
    /// else is withheld — not because the number is certainly wrong, but because nobody can
    /// say it is right. If that leaves nothing, the emergency number stands alone, which is
    /// exactly what docs/ГОДИШЕН-ЦИКЪЛ.md says happens when a spring window is missed.
    ///
    /// A development build shows every line, so the screen can be worked on.
    public func visible(
        on day: Date = Date(),
        build: BuildKind = .current,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [CrisisLine] {
        let candidates: [CrisisLine]
        switch build {
        case .debug:
            candidates = lines
        case .release:
            candidates = lines.filter {
                $0.isCurrent(on: day, validDays: validDays, calendar: calendar)
            }
        }

        let ordered = CrisisDirectory.ordered(candidates)
        return ordered.isEmpty ? [CrisisDirectory.emergency] : ordered
    }

    /// Emergency first, then the lines that answer at any hour, then the rest. The order is
    /// fixed and never personalised: a person must find the same thing in the same place.
    static func ordered(_ lines: [CrisisLine]) -> [CrisisLine] {
        func rank(_ line: CrisisLine) -> Int {
            if line.number.filter({ !$0.isWhitespace }) == "112" { return 0 }
            return line.hours.contains("денонощно") ? 1 : 2
        }
        return lines.enumerated()
            .sorted { left, right in
                let (a, b) = (rank(left.element), rank(right.element))
                return a == b ? left.offset < right.offset : a < b
            }
            .map(\.element)
    }

    /// For the maintenance window, not for the person using the app.
    public func stale(
        on day: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [CrisisLine] {
        lines.filter { !$0.isCurrent(on: day, validDays: validDays, calendar: calendar) }
    }

    static func date(from text: String?) -> Date? {
        guard let text, text.count == 10 else { return nil }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return Calendar(identifier: .gregorian).date(from: components)
    }
}
