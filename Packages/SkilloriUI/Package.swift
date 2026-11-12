// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkilloriUI",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SkilloriUI", targets: ["SkilloriUI"])],
    targets: [
        .target(name: "SkilloriUI", resources: [.copy("Resources/Fonts")]),
    ]
)
