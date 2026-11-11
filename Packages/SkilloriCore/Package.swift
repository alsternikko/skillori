// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkilloriCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SkilloriCore", targets: ["SkilloriCore"]),
        .executable(name: "skillori-probe", targets: ["SkilloriProbe"]),
    ],
    targets: [
        .target(name: "SkilloriCore"),
        // Internal read-only tool: prints the inventory for the current user. Not shipped.
        .executableTarget(name: "SkilloriProbe", dependencies: ["SkilloriCore"]),
        .testTarget(name: "SkilloriCoreTests", dependencies: ["SkilloriCore"]),
    ]
)
