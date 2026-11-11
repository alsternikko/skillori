// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkillwatchCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SkillwatchCore", targets: ["SkillwatchCore"]),
        .executable(name: "skillwatch-probe", targets: ["SkillwatchProbe"]),
    ],
    targets: [
        .target(name: "SkillwatchCore"),
        // Internal read-only tool: prints the inventory for the current user. Not shipped.
        .executableTarget(name: "SkillwatchProbe", dependencies: ["SkillwatchCore"]),
        .testTarget(name: "SkillwatchCoreTests", dependencies: ["SkillwatchCore"]),
    ]
)
