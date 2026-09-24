// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .library(name: "AtlasCore", targets: ["AtlasCore"]),
    .executable(name: "atlas-inspect", targets: ["AtlasCLI"])
]
var targets: [Target] = [
    .target(name: "AtlasCore"),
    .executableTarget(name: "AtlasCLI", dependencies: ["AtlasCore"]),
    .testTarget(name: "AtlasCoreTests", dependencies: ["AtlasCore"])
]
#if os(macOS)
products.append(.executable(name: "WorktreeAtlas", targets: ["WorktreeAtlas"]))
targets.append(.executableTarget(name: "WorktreeAtlas", dependencies: ["AtlasCore"]))
#endif
let package = Package(name: "WorktreeAtlas", platforms: [.macOS(.v14)], products: products, targets: targets)
