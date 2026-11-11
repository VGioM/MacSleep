import Foundation

/// Rules are one-off events, not a window: a Mac that comes on at 00:45,
/// after « Éteindre à 0:30 » and before « Réveiller à 8:30 », would stay on
/// until the next night. The daemon, run at boot and every hour, catches
/// that case: it schedules the missed sleep or shutdown `delay` from now,
/// tells whoever is logged in, and does it once per missed event, so a
/// cancelled catch-up is not scheduled again.
enum CatchUp {
    static let owner = "MacSleep rattrapage"
    /// Leaves time to cancel when the Mac was turned on on purpose.
    static let delay: TimeInterval = 10 * 60
    /// The last night event already dealt with (caught up, or there to begin with).
    static let stateURL = Rules.directory.appendingPathComponent("catchup.json")

    /// The night event the Mac is past without having slept: the latest rule
    /// event of the last 24 hours is a sleep or a shutdown, and the next wake
    /// of the rules is still far enough ahead. Without any wake rule there is
    /// no night to speak of, so nothing.
    static func missed(_ rules: [Rule], now: Date) -> (action: Action, date: Date)? {
        guard rules.contains(where: { $0.action == .wakeorpoweron }) else { return nil }
        // An event of the last minute is pmset's own business.
        let past = Rules.events(rules, after: now.addingTimeInterval(-24 * 3600),
                                until: now.addingTimeInterval(-60))
        guard let last = past.last, last.action.isNight else { return nil }
        // Rules.events is bounded by Helper.horizon, so is the wake looked for.
        let wake = Rules.events(rules, after: now, until: now.addingTimeInterval(Helper.horizon))
            .first { $0.action == .wakeorpoweron }
        guard let wake, wake.date.timeIntervalSince(now) > delay + 5 * 60 else { return nil }
        return last
    }

    // MARK: - Run as root

    /// From the daemon's hourly `--sync`.
    static func run(_ settings: Settings = Rules.load(), now: Date = Date()) {
        guard settings.catchUp, let event = missed(settings.rules, now: now) else { return }
        let key = PMSet.stamp(event.date)
        guard handled != key else { return }
        handled = key

        let at = now.addingTimeInterval(delay)
        let (status, output) = PMSet.run(["schedule", event.action.rawValue, PMSet.stamp(at), owner])
        guard status == 0 else {
            Log.write("rattrapage : pmset a échoué : \(output)")
            return
        }
        let what = event.action == .shutdown ? "Extinction" : "Mise en veille"
        Log.write("rattrapage : \(what.lowercased()) à \(Rules.format(Rules.minutes(of: at))) (règle de \(Rules.format(Rules.minutes(of: event.date))) manquée)")
        tellConsoleUser("\(what) à \(Rules.format(Rules.minutes(of: at))) : le Mac s'est rallumé pendant la nuit. Ouvrez MacSleep pour l'annuler.")
    }

    /// Saving rules in the middle of the night must not put the Mac to sleep
    /// straight away: whatever night event is already past counts as handled.
    static func markPast(_ rules: [Rule], now: Date = Date()) {
        handled = missed(rules, now: now).map { PMSet.stamp($0.date) }
    }

    private static var handled: String? {
        get { try? JSONDecoder().decode(String.self, from: Data(contentsOf: stateURL)) }
        set {
            guard let newValue else { try? FileManager.default.removeItem(at: stateURL); return }
            try? JSONEncoder().encode(newValue).write(to: stateURL, options: .atomic)
        }
    }

    /// A notification and the app's window, for the user at the screen. At
    /// the login window there is nobody to tell: the catch-up still happens.
    private static func tellConsoleUser(_ message: String) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: "/dev/console"),
              let uid = (attributes[.ownerAccountID] as? NSNumber)?.intValue, uid != 0,
              let user = attributes[.ownerAccountName] as? String else { return }
        let quoted = message.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        asUser(uid, user, ["/usr/bin/osascript", "-e", "display notification \"\(quoted)\" with title \"MacSleep\""])
        asUser(uid, user, ["/usr/bin/open", "-b", "com.macsleep.app"])
    }

    private static func asUser(_ uid: Int, _ user: String, _ command: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["asuser", String(uid), "/usr/bin/sudo", "-u", user] + command
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
