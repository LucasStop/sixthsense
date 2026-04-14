// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SharedServices",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SharedServices", targets: ["SharedServices"])
    ],
    dependencies: [
        .package(path: "../SixthSenseCore"),
    ],
    targets: [
        .target(
            name: "SharedServices",
            dependencies: ["SixthSenseCore"]
        ),
        .testTarget(
            name: "SharedServicesTests",
            dependencies: ["SharedServices"]
        )
    ]
)
