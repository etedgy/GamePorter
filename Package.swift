// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GamePorter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GamePorter",
            path: "Sources/GamePorter"
        )
    ]
)
