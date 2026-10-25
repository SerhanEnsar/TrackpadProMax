// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrackpadProMax",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "TrackpadProMax", targets: ["TrackpadProMax"]),
        .library(name: "TrackpadCore", targets: ["TrackpadCore"]),
    ],
    targets: [
        .target(name: "CMultitouch"),
        .target(name: "TrackpadCore", dependencies: ["CMultitouch"]),
        .executableTarget(name: "TrackpadProMax", dependencies: ["TrackpadCore"]),
        .testTarget(name: "TrackpadCoreTests", dependencies: ["TrackpadCore"]),
    ]
)
