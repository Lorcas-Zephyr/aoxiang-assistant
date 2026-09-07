// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AoxiangApp",
    platforms: [
        .iOS(.v15),
        // Host-only XCTest support. This package does not create a macOS app.
        .macOS(.v12),
    ],
    products: [
        .library(name: "AoxiangApp", targets: ["AoxiangApp"]),
    ],
    dependencies: [
        .package(path: "../AoxiangCore"),
    ],
    targets: [
        .target(
            name: "AoxiangApp",
            dependencies: ["AoxiangCore"],
            path: "Sources/AoxiangApp"
        ),
        .testTarget(
            name: "AoxiangAppTests",
            dependencies: ["AoxiangApp", "AoxiangCore"],
            path: "Tests/AoxiangAppTests"
        ),
    ]
)
