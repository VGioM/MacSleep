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
}

/// Everything the service runs from: the rules and their options.
struct Settings: Codable, Equatable {
    var rules: [Rule] = []
    /// Put the Mac back to sleep (or off) when it comes on during the night.
    var catchUp = true

    init(rules: [Rule] = [], catchUp: Bool = true) {
        self.rules = rules
        self.catchUp = catchUp
    }

    init(from decoder: Decoder) throws {
        // Version 1.0 wrote the bare list of rules.
        if let rules = try? decoder.singleValueContainer().decode([Rule].self) {
            self.init(rules: rules)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(rules: try c.decodeIfPresent([Rule].self, forKey: .rules) ?? [],
                  catchUp: try c.decodeIfPresent(Bool.self, forKey: .catchUp) ?? true)
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

    /// Every event the rules ask for after `start`, up to `end`.
    static func events(_ rules: [Rule], after start: Date, until end: Date) -> [(action: Action, date: Date)] {
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: start)
        var events: [(Action, Date)] = []
        var offset = 0
        while let day = calendar.date(byAdding: .day, value: offset, to: first), day <= end {
            let weekday = Weekday(day)
            for rule in rules where rule.days.contains(weekday) {
                guard let date = calendar.date(bySettingHour: rule.at / 60, minute: rule.at % 60,
                                               second: 0, of: day),
                      date > start, date <= end else { continue }
                events.append((rule.action, date))
            }
            offset += 1
        }
        return events.sorted { $0.1 < $1.1 }
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
