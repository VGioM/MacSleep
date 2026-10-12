import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        // The root helper runs this same binary without UI.
        let args = CommandLine.arguments
        if args.contains("--sync") { exit(Helper.sync()) }
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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
