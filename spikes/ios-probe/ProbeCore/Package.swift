// swift-tools-version: 6.0
// Pure Swift logic of the S3 iOS probe (docs/spikes/S3.md §6.7). Foundation only, so `swift test` runs on
// Windows/Linux. The app target compiles Sources/ProbeCore directly (no SwiftPM inside Xcode, §6.2).
import PackageDescription

let package = Package(
    name: "ProbeCore",
    products: [
        .library(name: "ProbeCore", targets: ["ProbeCore"]),
    ],
    targets: [
        .target(name: "ProbeCore"),
        .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"]),
    ]
)
