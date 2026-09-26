// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GraphicDocApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "GraphicDocApp", path: "Sources/GraphicDocApp")
    ]
)
