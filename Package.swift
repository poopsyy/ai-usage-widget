// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIUsage",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AIUsage", targets: ["AIUsage"]),
        .executable(name: "UsageBridge", targets: ["UsageBridge"]),
        .executable(name: "UsageChecks", targets: ["UsageChecks"])
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "AIUsage", dependencies: ["UsageCore"]),
        .executableTarget(name: "UsageBridge", dependencies: ["UsageCore"]),
        .executableTarget(name: "UsageChecks", dependencies: ["UsageCore"], path: "Tests/UsageCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
