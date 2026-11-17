// swift-tools-version:5.10
import PackageDescription

// Plain SwiftPM package: no Xcode project needed. ./build.sh wraps the binary into PureSweep.app.
let package = Package(
    name: "PureSweep",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PureSweep", path: "Sources/PureSweep")
    ]
)
