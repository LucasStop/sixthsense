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

        // Shared services (camera, network, overlay, accessibility, input, permissions)
        .target(
            name: "SharedServices",
            dependencies: ["SixthSenseCore"],
            path: "Packages/SharedServices/Sources/SharedServices"
        ),

        // Feature modules
        .target(
            name: "HandCommandModule",
            dependencies: ["SixthSenseCore", "SharedServices"],
            path: "Packages/HandCommandModule/Sources/HandCommandModule"
        ),
        .target(
            name: "GazeShiftModule",
            dependencies: ["SixthSenseCore", "SharedServices"],
            path: "Packages/GazeShiftModule/Sources/GazeShiftModule"
        ),
        .target(
            name: "AirCursorModule",
            dependencies: ["SixthSenseCore", "SharedServices"],
            path: "Packages/AirCursorModule/Sources/AirCursorModule"
        ),
        .target(
            name: "PortalViewModule",
            dependencies: ["SixthSenseCore", "SharedServices"],
            path: "Packages/PortalViewModule/Sources/PortalViewModule"
        ),
        .target(
            name: "GhostDropModule",
            dependencies: ["SixthSenseCore", "SharedServices"],
            path: "Packages/GhostDropModule/Sources/GhostDropModule"
        ),
        .target(
            name: "NotchBarModule",
            dependencies: ["SixthSenseCore", "SharedServices"],
            path: "Packages/NotchBarModule/Sources/NotchBarModule"
        ),

        // Main app executable
        .executableTarget(
            name: "SixthSenseApp",
            dependencies: [
                "SixthSenseCore",
                "SharedServices",
                "HandCommandModule",
                "GazeShiftModule",
                "AirCursorModule",
                "PortalViewModule",
                "GhostDropModule",
                "NotchBarModule",
            ],
            path: "SixthSenseApp"
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
    ]
)
