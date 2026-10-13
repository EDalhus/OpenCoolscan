// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenCoolscan",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Pinned exactly: OpenCoolscan only changes when this is bumped on purpose.
        .package(url: "https://github.com/EDalhus/CoolscanKit.git", exact: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "OpenCoolscan",
            dependencies: ["CoolscanKit"],
            path: "Sources/OpenCoolscan",
            resources: [.copy("Resources")]
        )
    ]
)
