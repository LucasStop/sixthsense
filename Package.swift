// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SixthSense",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SixthSense", targets: ["SixthSenseApp"])
    ],
    dependencies: [],
    targets: [
        // Core protocols and types
        .target(
            name: "SixthSenseCore",
            path: "Packages/SixthSenseCore/Sources/SixthSenseCore"
        ),

        // Shared services (camera, overlay, accessibility, input, permissions)
        .target(
            name: "SharedServices",
            dependencies: ["SixthSenseCore"],
            path: "Packages/SharedServices/Sources/SharedServices"
        ),

        // HandCommand — the only feature module.
        .target(
            name: "HandCommandModule",
            dependencies: ["SixthSenseCore", "SharedServices"],
            path: "Packages/HandCommandModule/Sources/HandCommandModule"
        ),

        // Main app executable
        .executableTarget(
            name: "SixthSenseApp",
            dependencies: [
                "SixthSenseCore",
                "SharedServices",
                "HandCommandModule",
            ],
            path: "SixthSenseApp",
            exclude: ["Resources/Info.plist"]
        ),

        // Test mocks shared between test targets.
        .target(
            name: "SharedServicesMocks",
            dependencies: ["SharedServices", "SixthSenseCore"],
            path: "Packages/SharedServices/Mocks"
        ),

        // Tests
        .testTarget(
            name: "SixthSenseCoreTests",
            dependencies: ["SixthSenseCore"],
            path: "Packages/SixthSenseCore/Tests/SixthSenseCoreTests"
        ),
        .testTarget(
            name: "SharedServicesTests",
            dependencies: ["SharedServices"],
            path: "Packages/SharedServices/Tests/SharedServicesTests"
        ),
        .testTarget(
            name: "HandCommandModuleTests",
            dependencies: ["HandCommandModule", "SixthSenseCore", "SharedServices", "SharedServicesMocks"],
            path: "Packages/HandCommandModule/Tests/HandCommandModuleTests"
        ),
    ]
)
