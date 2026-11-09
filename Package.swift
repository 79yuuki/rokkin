// swift-tools-version:5.9
import PackageDescription

var targets: [Target] = [
    // Foundation-only logic (models, stats, persistence, Claude Code bridge). Builds and tests on any platform.
    .target(name: "RokkinCore"),
    .testTarget(name: "RokkinCoreTests", dependencies: ["RokkinCore"]),
]
var products: [Product] = [
    .library(name: "RokkinCore", targets: ["RokkinCore"]),
]

#if os(macOS)
// The menu bar app itself (SwiftUI + AppKit).
targets.append(.executableTarget(name: "Rokkin", dependencies: ["RokkinCore"]))
products.append(.executable(name: "Rokkin", targets: ["Rokkin"]))
#endif

let package = Package(
    name: "Rokkin",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
