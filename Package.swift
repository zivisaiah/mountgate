// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MountGate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MountGate", targets: ["MountGateApp"]),
        .library(name: "MountGateCore", targets: ["MountGateCore"]),
    ],
    dependencies: [
        // Command Line Tools don't ship XCTest/Testing; pull swift-testing explicitly.
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.12.0"),
    ],
    targets: [
        .target(name: "MountGateCore"),
        .executableTarget(
            name: "MountGateApp",
            dependencies: ["MountGateCore"]
        ),
        .testTarget(
            name: "MountGateCoreTests",
            dependencies: [
                "MountGateCore",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
