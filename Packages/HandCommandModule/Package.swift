// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HandCommandModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HandCommandModule", targets: ["HandCommandModule"])
    ],
    dependencies: [
        .package(path: "../SixthSenseCore"),
        .package(path: "../SharedServices"),
    ],
    targets: [
        .target(
            name: "HandCommandModule",
            dependencies: ["SixthSenseCore", "SharedServices"]
        )
    ]
)
