// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SixthSenseCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SixthSenseCore", targets: ["SixthSenseCore"])
    ],
    targets: [
        .target(name: "SixthSenseCore"),
        .testTarget(name: "SixthSenseCoreTests", dependencies: ["SixthSenseCore"])
    ]
)
