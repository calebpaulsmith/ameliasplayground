// swift-tools-version:5.9
import PackageDescription

// AmeliaCore is the rendering-agnostic Game Core for "Amelia's Bus Adventure".
//
// It contains NO RealityKit / SwiftUI / GameController imports, so it builds and
// unit-tests on any platform (incl. plain `swift test` on a CI runner without a
// GPU or simulator). The tvOS app links this package and provides the rendering
// and input adapters. See docs/tvos/TECHNICAL_ARCHITECTURE.md.
let package = Package(
    name: "AmeliaCore",
    platforms: [
        .macOS(.v13),
        .tvOS(.v17),
        .iOS(.v16)
    ],
    products: [
        .library(name: "AmeliaCore", targets: ["AmeliaCore"])
    ],
    targets: [
        .target(
            name: "AmeliaCore",
            path: "Sources/AmeliaCore"
        ),
        .testTarget(
            name: "AmeliaCoreTests",
            dependencies: ["AmeliaCore"],
            path: "Tests/AmeliaCoreTests"
        )
    ]
)
