// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirCursorModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AirCursorModule", targets: ["AirCursorModule"])
    ],
    dependencies: [
        .package(path: "../SixthSenseCore"),
        .package(path: "../SharedServices"),
    ],
    targets: [
        .target(
            name: "AirCursorModule",
            dependencies: ["SixthSenseCore", "SharedServices"]
        )
    ]
)
