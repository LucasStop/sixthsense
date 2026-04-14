// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GhostDropModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GhostDropModule", targets: ["GhostDropModule"])
    ],
    dependencies: [
        .package(path: "../SixthSenseCore"),
        .package(path: "../SharedServices"),
    ],
    targets: [
        .target(
            name: "GhostDropModule",
            dependencies: ["SixthSenseCore", "SharedServices"]
        )
    ]
)
