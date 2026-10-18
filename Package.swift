// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ConvertDock",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "ConvertDock",
            path: "Sources/ConvertDock",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
