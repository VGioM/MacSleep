import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        // The root helper runs this same binary without UI.
        let args = CommandLine.arguments
        if args.contains("--sync") {
            let status = Helper.sync()
            CatchUp.run()
            exit(status)
        }
        if args.contains("--uninstall") { exit(Helper.uninstall()) }
        if let i = args.firstIndex(of: "--install"), i + 1 < args.count {
            exit(Helper.install(rulesFile: args[i + 1]))
        }
        MacSleepApp.main()
    }
}

struct MacSleepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("MacSleep", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(SelfUpdate.menuTitle) { SelfUpdate.checkNow() }
                AutomaticUpdates()
            }
        }
    }
}

/// « Rechercher automatiquement les mises à jour », cochable dans le menu MacSleep.
private struct AutomaticUpdates: View {
    @AppStorage(SelfUpdate.automaticKey) private var automatic = true

    var body: some View {
        Toggle(SelfUpdate.automaticTitle, isOn: $automatic)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Les builds de développement ne se mettent pas à jour.
        #if !DEBUG
        SelfUpdate.start(repo: "VGioM/MacSleep")
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
