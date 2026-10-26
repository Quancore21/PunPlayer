// swift-tools-version:5.7
import PackageDescription

// This package exists only to run the platform-independent core logic
// (PunPlayer/Core) as unit tests with `swift test`, without a simulator.
// The same source files are compiled into the app target by project.yml.
let package = Package(
    name: "PunCore",
    platforms: [.macOS(.v12), .iOS(.v16)],
    products: [
        .library(name: "PunCore", targets: ["PunCore"])
    ],
    targets: [
        .target(name: "PunCore", path: "PunPlayer/Core"),
        .testTarget(name: "PunCoreTests", dependencies: ["PunCore"], path: "Tests/PunCoreTests")
    ]
)
