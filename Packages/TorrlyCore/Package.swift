// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TorrlyCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TorrlyCore", targets: ["TorrlyCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup", exact: "2.14.3"),
    ],
    targets: [
        .target(
            name: "TorrlyCore",
            dependencies: ["SwiftSoup"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TorrlyCoreTests",
            dependencies: ["TorrlyCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
