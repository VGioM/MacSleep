// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacSleep",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacSleep",
            path: "Sources/MacSleep",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Run with Tests/run-unit.sh (or `swift test`).
        .testTarget(
            name: "MacSleepTests",
            dependencies: ["MacSleep"],
            path: "Tests/MacSleepTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
