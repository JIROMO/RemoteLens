// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RemoteLens",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "VirtualDisplayBridge",
            path: "Sources/VirtualDisplayBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "RemoteLens",
            dependencies: ["VirtualDisplayBridge"],
            path: "Sources/RemoteLens"
        )
    ]
)
