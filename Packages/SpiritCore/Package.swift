// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpiritCore",
    products: [
        .library(name: "SpiritCore", targets: ["SpiritCore"]),
        .executable(name: "SpiritBridge", targets: ["SpiritBridge"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "SpiritCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "SpiritBridge", dependencies: ["SpiritCore"]),
        .testTarget(name: "SpiritCoreTests", dependencies: ["SpiritCore"])
    ]
)
