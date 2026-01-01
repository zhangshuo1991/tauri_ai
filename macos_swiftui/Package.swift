// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIHubApp",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "AIHubApp", targets: ["AIHubApp"])
    ],
    targets: [
        .executableTarget(
            name: "AIHubApp",
            path: "Sources/AIHubApp",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
