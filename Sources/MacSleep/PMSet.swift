import Foundation

/// A one-off event from `pmset -g sched`, e.g.
/// ` [0]  wakepoweron at 10/14/26 07:00:00 by 'MacSleep'`.
struct OneOffEvent: Identifiable, Equatable {
    let id: String
    let type: String
    let date: Date?
    let owner: String?

    var fromRule: Bool { owner == Helper.owner }

    /// One-off wakes added from the window (or with pmset in the Terminal).
    /// The daemon's catch-ups count too: they can be cancelled the same way.
    var isManual: Bool {
        [Helper.manualOwner, CatchUp.owner, "pmset"].contains(owner ?? "") && date != nil
    }
}

/// What macOS has actually recorded.
struct SystemSchedule: Equatable {
    var repeating: [String] = []
    var oneOff: [OneOffEvent] = []
}

/// Talks to `/usr/bin/pmset`. Reading needs no rights.
enum PMSet {
    static func read() -> SystemSchedule {
        let (_, output) = run(["-g", "sched"])
        var schedule = SystemSchedule()
        var section = ""
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix(":") && !line.hasPrefix("[") {
                section = line
            } else if section.hasPrefix("Repeating") {
                schedule.repeating.append(line)
            } else if section.hasPrefix("Scheduled") {
                schedule.oneOff.append(parseOneOff(line))
            }
        }
        return schedule
    }

    /// pmset's own date format for `schedule`.
    static func stamp(_ date: Date) -> String {
        formatter("MM/dd/yy HH:mm:ss").string(from: date)
    }

    @discardableResult
    static func run(_ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus,
                String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parseOneOff(_ line: String) -> OneOffEvent {
        let pattern = #"\]\s+(\S+) at (\d{1,2}/\d{1,2}/\d{2,4} \d{1,2}:\d{2}:\d{2})(?: by '([^']*)')?"#
        guard let match = line.firstMatch(of: try! Regex(pattern)),
              let type = match.output[1].substring,
              let when = match.output[2].substring else {
            return OneOffEvent(id: line, type: line, date: nil, owner: nil)
        }
        let text = String(when)
        // Depending on the macOS version the year has two or four digits.
        let year = text.prefix { $0 != " " }.split(separator: "/").last ?? ""
        let date = formatter(year.count == 4 ? "MM/dd/yyyy HH:mm:ss" : "MM/dd/yy HH:mm:ss").date(from: text)
        // pmset lists « wakeorpoweron » under its internal name.
        let normalized = type == "wakepoweron" ? "wakeorpoweron" : String(type)
        return OneOffEvent(id: line, type: normalized, date: date,
                           owner: match.output[3].substring.map(String.init))
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}

/// Runs a shell line behind the standard administrator password prompt.
enum Admin {
    /// Returns an error message, or nil on success.
    static func run(_ script: String) -> String? {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?
            .executeAndReturnError(&error)
        guard let error else { return nil }
        if error[NSAppleScript.errorNumber] as? Int == -128 { return "Opération annulée." }
        let message = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
        Log.write("commande admin en échec : \(message)")
        return message
    }
}

func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

enum Log {
    /// The daemon runs as root and logs system-wide.
    static let url = getuid() == 0
        ? URL(fileURLWithPath: "/Library/Logs/MacSleep.log")
        : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MacSleep.log")

    static func write(_ message: String) {
        let stamp = Date().formatted(date: .numeric, time: .standard)
        let line = Data("[\(stamp)] \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }
}
