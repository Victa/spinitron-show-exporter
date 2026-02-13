// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpinitronShowExporter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SpinitronShowExporter",
            path: "Sources"
        )
    ]
)
