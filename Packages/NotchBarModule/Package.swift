// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchBarModule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotchBarModule", targets: ["NotchBarModule"])
    ],
    dependencies: [
        .package(path: "../SixthSenseCore"),
        .package(path: "../SharedServices"),
    ],
    targets: [
        .target(
            name: "NotchBarModule",
            dependencies: ["SixthSenseCore", "SharedServices"]
        )
    ]
)
