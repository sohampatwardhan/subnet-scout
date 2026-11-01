// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScannerCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "ScannerCore", targets: ["ScannerCore"]),
    ],
    targets: [
        .target(name: "ScannerCore"),
        .testTarget(
            name: "ScannerCoreTests",
            dependencies: ["ScannerCore"]
        ),
    ]
)
