// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ConvertDock",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Encodeur WebP de Google (licence BSD), empaqueté pour SwiftPM par SDWebImage.
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", from: "1.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "ConvertDock",
            dependencies: [
                "CLame",
                .product(name: "libwebp", package: "libwebp-Xcode"),
            ],
            path: "Sources/ConvertDock",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Encodeur MP3 LAME 3.100 (licence LGPL, voir Sources/CLame/COPYING).
        .target(
            name: "CLame",
            path: "Sources/CLame",
            exclude: ["COPYING"],
            sources: ["libmp3lame"],
            publicHeadersPath: "include",
            cSettings: [
                .define("HAVE_CONFIG_H"),
                .headerSearchPath("libmp3lame"),
                .unsafeFlags(["-w"]),
            ]
        ),
    ]
)
