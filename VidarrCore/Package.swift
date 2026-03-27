// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VidarrCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "VidarrCore",
            targets: ["VidarrCore"]
        )
    ],
    targets: [
        .target(
            name: "VidarrCore"
        ),
        .testTarget(
            name: "VidarrCoreTests",
            dependencies: ["VidarrCore"]
        )
    ]
)
