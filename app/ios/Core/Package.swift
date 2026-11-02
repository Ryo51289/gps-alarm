// swift-tools-version: 6.0
// NapStop Trip Engine, Swift port (docs/specs/T13.md). Behaviour contract: docs/specs/T10.md + T12.md §5.
// Module `Trip` uses only the Swift standard library (no Foundation), so results are identical on Linux and Apple.
import PackageDescription

let package = Package(
    name: "NapStopCore",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "Trip", targets: ["Trip"]),
    ],
    targets: [
        .target(name: "Trip"),
        .testTarget(name: "TripTests", dependencies: ["Trip"]),
    ]
)
