// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TokenMac",
            path: "Sources/TokenMac"
        ),
        .testTarget(
            name: "TokenMacTests",
            dependencies: ["TokenMac"],
            path: "Tests/TokenMacTests"
        ),
    ]
)
