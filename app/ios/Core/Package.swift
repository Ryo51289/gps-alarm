// swift-tools-version: 6.0
// NapStop Trip Engine, Swift port (docs/specs/T13.md). Behaviour contract: docs/specs/T10.md + T12.md §5.
// Module `Trip` uses only the Swift standard library (no Foundation), so results are identical on Linux and Apple.
// T17: `TripRuntime` (Foundation only, Swift 6 mode, tested on Linux) and `NapStopIOS` (Apple frameworks inside
// `#if os(iOS)`, Swift 5 mode because Sendable annotations differ between the xtool SDK and the CI Xcode SDK).
import PackageDescription

let package = Package(
    name: "NapStopCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "Trip", targets: ["Trip"]),
        .library(name: "TripRuntime", targets: ["TripRuntime"]),
        .library(name: "NapStopIOS", targets: ["NapStopIOS"]),
    ],
    targets: [
        .target(name: "Trip"),
        .target(name: "TripRuntime", dependencies: ["Trip"]),
        .target(name: "NapStopIOS", dependencies: ["Trip", "TripRuntime"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "TripTests", dependencies: ["Trip"]),
        .testTarget(name: "TripRuntimeTests", dependencies: ["Trip", "TripRuntime"]),
        // T23.3: map wire format (MapWire.swift, Foundation only), parity with fixtures/map_wire.
        .testTarget(name: "NapStopIOSTests", dependencies: ["NapStopIOS"]),
    ]
)
