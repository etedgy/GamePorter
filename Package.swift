// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GamePorter",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Auto-update framework (checks an appcast, downloads + installs new versions).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "GamePorter",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/GamePorter"
        )
    ]
)
