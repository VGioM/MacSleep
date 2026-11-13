import Foundation

/// The root side. `pmset repeat` holds a single sleep/wake pair, so MacSleep
/// turns its rules into one-off `pmset schedule` events instead, tagged with
/// the owner « MacSleep ». A copy of this binary in PrivilegedHelperTools, run
/// by a LaunchDaemon at boot and every hour, keeps the next `horizon` of events
/// in step with the rules. Being a root-owned copy, it keeps working if the
/// app is moved or deleted, and the user's copy cannot be swapped under it.
enum Helper {
    static let label = "com.macsleep.daemon"
    static let path = "/Library/PrivilegedHelperTools/com.macsleep.helper"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    static let owner = "MacSleep"
    static let manualOwner = "MacSleep ponctuel"
    static let horizon: TimeInterval = 8 * 24 * 3600

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistPath) }

    /// The root copy is this very binary. After an update of the app it is
    /// not, until the rules are saved again.
    static var isCurrent: Bool {
        guard let executable = Bundle.main.executablePath else { return true }
        return FileManager.default.contentsEqual(atPath: executable, andPath: path)
    }

    // MARK: - Run from the app, behind the admin prompt

    /// Copies this binary into place, then lets it install itself as root.
    static func installScript(rulesFile: String) -> String? {
        guard let executable = Bundle.main.executablePath else { return nil }
        return [
            "mkdir -p /Library/PrivilegedHelperTools",
            "cp \(shellQuote(executable)) \(shellQuote(path))",
            "chown root:wheel \(shellQuote(path))",
            "chmod 755 \(shellQuote(path))",
            "\(shellQuote(path)) --install \(shellQuote(rulesFile))",
        ].joined(separator: " && ")
    }

    static var uninstallScript: String { "\(shellQuote(path)) --uninstall" }

    // MARK: - Run as root

    static func install(rulesFile: String) -> Int32 {
        let fm = FileManager.default
        do {
            let settings = try Rules.read(URL(fileURLWithPath: rulesFile))
            try fm.createDirectory(at: Rules.directory, withIntermediateDirectories: true)
            try Rules.encode(settings).write(to: Rules.url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: Rules.url.path)

            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [path, "--sync"],
                "RunAtLoad": true,
                // Hourly; launchd runs a slot missed during sleep on wake.
                "StartCalendarInterval": ["Minute": 0],
                "StandardErrorPath": Log.url.path,
            ]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: URL(fileURLWithPath: plistPath), options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plistPath)
        } catch {
            return fail("installation impossible : \(error.localizedDescription)")
        }

        // The rules replace pmset's single repeating pair.
        PMSet.run(["repeat", "cancel"])
        let status = sync()
        CatchUp.markPast(Rules.load())

        launchctl("bootout", "system/\(label)")
        let (loaded, output) = launchctl("bootstrap", "system", plistPath)
        if loaded != 0 { return fail("launchctl a refusé le service (\(loaded)) : \(output)") }
        Log.write("service installé")
        return status
    }

    static func uninstall() -> Int32 {
        let status = sync(Settings())
        launchctl("bootout", "system/\(label)")
        for item in [plistPath, Rules.directory.path, path] {
            try? FileManager.default.removeItem(atPath: item)
        }
        Log.write("service supprimé")
        return status
    }

    /// Adds the events the rules want in the coming `horizon` and cancels the
    /// MacSleep events they no longer want. Leaves every other event alone.
    @discardableResult
    static func sync(_ settings: Settings = Rules.load()) -> Int32 {
        // Events about to fire are left as they are.
        let start = Date().addingTimeInterval(60)
        let wanted = Set(Rules.events(settings.rules, exceptions: settings.exceptions, after: start, until: start.addingTimeInterval(horizon))
            .map { key($0.action.rawValue, $0.date) })
        let current = Set(PMSet.read().oneOff.compactMap { event -> String? in
            guard event.fromRule, let date = event.date, date > start else { return nil }
            return key(event.type, date)
        })

        var failures = 0
        func pmset(_ verb: [String], _ entry: String) {
            let parts = entry.split(separator: "|").map(String.init)
            let (status, output) = PMSet.run(["schedule"] + verb + [parts[0], parts[1], owner])
            if status != 0 {
                failures += 1
                Log.write("pmset schedule \(verb.joined()) \(parts[0]) \(parts[1]) a échoué : \(output)")
            }
        }
        for entry in current.subtracting(wanted).sorted() { pmset(["cancel"], entry) }
        for entry in wanted.subtracting(current).sorted() { pmset([], entry) }

        let added = wanted.subtracting(current).count, removed = current.subtracting(wanted).count
        if added + removed > 0 {
            Log.write("synchro : \(added) ajouté(s), \(removed) retiré(s), \(failures) échec(s)")
        }
        return failures == 0 ? 0 : 1
    }

    private static func key(_ type: String, _ date: Date) -> String {
        "\(type)|\(PMSet.stamp(date))"
    }

    private static func fail(_ message: String) -> Int32 {
        Log.write(message)
        FileHandle.standardError.write(Data("MacSleep : \(message)\n".utf8))
        return 1
    }

    @discardableResult
    private static func launchctl(_ args: String...) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
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
}
