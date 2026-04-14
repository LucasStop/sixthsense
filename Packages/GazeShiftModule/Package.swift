// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GazeShiftModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GazeShiftModule", targets: ["GazeShiftModule"])
    ],
    dependencies: [
        .package(path: "../SixthSenseCore"),
        .package(path: "../SharedServices"),
    ],
    targets: [
        .target(
            name: "GazeShiftModule",
            dependencies: ["SixthSenseCore", "SharedServices"]
        )
    ]
)
