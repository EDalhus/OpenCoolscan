// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenCoolscan",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "OpenCoolscan",
            path: "Sources/OpenCoolscan",
            resources: [.copy("Resources")]
        )
    ]
)
