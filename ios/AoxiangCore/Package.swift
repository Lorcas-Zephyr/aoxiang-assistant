// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AoxiangCore",
    platforms: [
        .iOS(.v15),
        // Host-only XCTest support. The Xcode products remain iPhone/iPad only.
        .macOS(.v12),
    ],
    products: [
        .library(name: "AoxiangCore", targets: ["AoxiangCore"]),
    ],
    targets: [
        .target(
            name: "AoxiangCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AoxiangCoreTests",
            dependencies: ["AoxiangCore"]
        ),
    ]
)
