// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortalViewModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PortalViewModule", targets: ["PortalViewModule"])
    ],
    dependencies: [
        .package(path: "../SixthSenseCore"),
        .package(path: "../SharedServices"),
    ],
    targets: [
        .target(
            name: "PortalViewModule",
            dependencies: ["SixthSenseCore", "SharedServices"]
        )
    ]
)
