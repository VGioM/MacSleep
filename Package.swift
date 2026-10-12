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
        )
    ]
)
