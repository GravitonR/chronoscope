// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChronoScope",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "ChronoScopeCore", targets: ["ChronoScopeCore"]),
        .executable(name: "ChronoScopeMac", targets: ["ChronoScopeMac"])
    ],
    targets: [
        .target(
            name: "ChronoScopeCore",
            path: "Sources/ChronoScopeCore"
        ),
        .executableTarget(
            name: "ChronoScopeMac",
            dependencies: ["ChronoScopeCore"],
            path: "Sources/ChronoScopeApp"
        ),
        .testTarget(
            name: "ChronoScopeCoreTests",
            dependencies: ["ChronoScopeCore"],
            path: "Tests/ChronoScopeCoreTests"
        )
    ]
)
