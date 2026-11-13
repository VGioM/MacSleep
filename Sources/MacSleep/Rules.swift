import Foundation

/// What a rule does. The raw values are `pmset schedule` event types.
enum Action: String, Codable, CaseIterable, Identifiable {
    case sleep, shutdown, wakeorpoweron

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sleep: "Mettre en veille"
        case .shutdown: "Éteindre"
        case .wakeorpoweron: "Réveiller ou allumer"
        }
    }

    var noun: String {
        switch self {
        case .sleep: "Veille"
        case .shutdown: "Extinction"
        case .wakeorpoweron: "Réveil"
        }
    }

    var symbol: String {
        switch self {
        case .sleep: "moon.zzz.fill"
        case .shutdown: "power"
        case .wakeorpoweron: "sunrise.fill"
        }
    }

    var isNight: Bool { self != .wakeorpoweron }
}

/// Days in pmset's order, Monday first.
enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case mon, tue, wed, thu, fri, sat, sun

    var id: Int { rawValue }
    var initial: String { ["L", "M", "M", "J", "V", "S", "D"][rawValue] }
    var name: String { ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"][rawValue] }

    /// Calendar counts Sunday as 1.
    init(_ date: Date) {
        self.init(rawValue: (Calendar.current.component(.weekday, from: date) + 5) % 7)!
    }

    static let all = Set(allCases)
}

/// One line of the schedule: an action, at a time, on some days.
struct Rule: Codable, Identifiable, Equatable {
    var id = UUID()
    var action = Action.sleep
    /// Minutes since midnight.
    var at = 23 * 60 + 30
    var days = Weekday.all
    /// Switched off: the rule stays in the list but does nothing.
    var enabled = true
}

extension Rule {
    // In an extension, so the memberwise initialiser stays.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  action: try c.decodeIfPresent(Action.self, forKey: .action) ?? .sleep,
                  at: try c.decodeIfPresent(Int.self, forKey: .at) ?? 23 * 60 + 30,
                  days: try c.decodeIfPresent(Set<Weekday>.self, forKey: .days) ?? Weekday.all,
                  // Versions before 1.2 had no switch: every rule was on.
                  enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true)
    }
}

/// One occurrence of a rule, skipped or moved, this once (« ce soir seulement »).
struct Exception: Codable, Equatable {
    var rule: UUID
    /// When the rule would have acted.
    var date: Date
    /// When it acts instead; nil: not at all.
    var moved: Date?

    /// Still to come, or the occurrence it replaces is: worth keeping.
    func isCurrent(now: Date) -> Bool { max(date, moved ?? date) > now }
}

/// Everything the service runs from: the rules and their options.
struct Settings: Codable, Equatable {
    var rules: [Rule] = []
    /// Put the Mac back to sleep (or off) when it comes on during the night.
    var catchUp = true
    var exceptions: [Exception] = []

    init(rules: [Rule] = [], catchUp: Bool = true, exceptions: [Exception] = []) {
        self.rules = rules
        self.catchUp = catchUp
        self.exceptions = exceptions
    }

    init(from decoder: Decoder) throws {
        // Version 1.0 wrote the bare list of rules.
        if let rules = try? decoder.singleValueContainer().decode([Rule].self) {
            self.init(rules: rules)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(rules: try c.decodeIfPresent([Rule].self, forKey: .rules) ?? [],
                  catchUp: try c.decodeIfPresent(Bool.self, forKey: .catchUp) ?? true,
                  exceptions: try c.decodeIfPresent([Exception].self, forKey: .exceptions) ?? [])
    }

    /// Without the exceptions that are over (or whose rule is gone): the
    /// catch-up still needs those of the last night, so 24 hours are kept.
    func pruned(now: Date = Date()) -> Settings {
        var s = self
        let ids = Set(rules.map(\.id))
        s.exceptions = exceptions.filter { ids.contains($0.rule) && $0.isCurrent(now: now.addingTimeInterval(-24 * 3600)) }
        return s
    }
}

/// The rules live in a root-owned file: the app writes it through the admin
/// prompt, the daemon reads it.
enum Rules {
    static let directory = URL(fileURLWithPath: "/Library/Application Support/MacSleep")
    static let url = directory.appendingPathComponent("rules.json")

    static func read(_ url: URL = url) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(contentsOf: url))
    }

    static func load() -> Settings {
        (try? read()) ?? Settings()
    }

    static func encode(_ settings: Settings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    /// Every event the rules ask for after `start`, up to `end`: the rules
    /// switched on, each occurrence skipped or moved by its exception.
    static func events(_ rules: [Rule], exceptions: [Exception] = [], after start: Date, until end: Date) -> [(action: Action, date: Date)] {
        let calendar = Calendar.current
        // A day earlier: an occurrence of yesterday may have been moved past `start`.
        let first = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start)) ?? start
        var events: [(Action, Date)] = []
        var offset = 0
        while let day = calendar.date(byAdding: .day, value: offset, to: first), day <= end {
            let weekday = Weekday(day)
            for rule in rules where rule.enabled && rule.days.contains(weekday) {
                guard var date = calendar.date(bySettingHour: rule.at / 60, minute: rule.at % 60,
                                               second: 0, of: day) else { continue }
                if let e = exceptions.first(where: { $0.rule == rule.id && $0.date == date }) {
                    guard let moved = e.moved else { continue }
                    date = moved
                }
                guard date > start, date <= end else { continue }
                events.append((rule.action, date))
            }
            offset += 1
        }
        return events.sorted { $0.1 < $1.1 }
    }

    /// The next time a rule acts after `now`, as the rule has it (before any exception).
    static func next(_ rule: Rule, after now: Date) -> Date? {
        var on = rule
        on.enabled = true
        return events([on], after: now, until: now.addingTimeInterval(8 * 24 * 3600)).first?.date
    }

    static func describe(_ days: Set<Weekday>) -> String {
        switch days {
        case Weekday.all: "tous les jours"
        case [.mon, .tue, .wed, .thu, .fri]: "en semaine"
        case [.sat, .sun]: "le week-end"
        default: "le " + days.sorted { $0.rawValue < $1.rawValue }.map(\.name).joined(separator: ", ")
        }
    }

    static func format(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func minutes(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func date(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                              second: 0, of: Date()) ?? Date()
    }
}
