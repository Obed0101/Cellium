// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cellium",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CelliumCore", targets: ["CelliumCore"]),
        .library(name: "CelliumDarwin", targets: ["CelliumDarwin"]),
        .library(name: "CelliumStore", targets: ["CelliumStore"]),
        .library(name: "CelliumAutomation", targets: ["CelliumAutomation"]),
        .executable(name: "cellium", targets: ["CelliumCLI"]),
        .executable(name: "CelliumApp", targets: ["CelliumApp"])
    ],
    targets: [
        .target(
            name: "CelliumCore",
            path: "Packages/CelliumCore/Sources/CelliumCore"
        ),
        .target(
            name: "CelliumDarwin",
            dependencies: ["CelliumCore"],
            path: "Packages/CelliumDarwin/Sources/CelliumDarwin",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "CelliumStore",
            dependencies: ["CelliumCore"],
            path: "Packages/CelliumStore/Sources/CelliumStore"
        ),
        .target(
            name: "CelliumIntelligence",
            dependencies: ["CelliumCore"],
            path: "Packages/CelliumIntelligence/Sources/CelliumIntelligence"
        ),
        .target(
            name: "CelliumAutomation",
            dependencies: ["CelliumCore"],
            path: "Packages/CelliumAutomation/Sources/CelliumAutomation"
        ),
        .executableTarget(
            name: "CelliumCLI",
            dependencies: ["CelliumCore", "CelliumDarwin", "CelliumStore"],
            path: "CLI"
        ),
        .executableTarget(
            name: "CelliumApp",
            dependencies: ["CelliumCore", "CelliumDarwin", "CelliumStore", "CelliumAutomation"],
            path: "App",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "CelliumCoreTests",
            dependencies: ["CelliumCore"],
            path: "Tests/CelliumCoreTests"
        ),
        .testTarget(
            name: "CelliumDarwinTests",
            dependencies: ["CelliumCore", "CelliumDarwin"],
            path: "Tests/CelliumDarwinTests"
        ),
        .testTarget(
            name: "CelliumStoreTests",
            dependencies: ["CelliumCore", "CelliumStore"],
            path: "Tests/CelliumStoreTests"
        )
    ]
)
