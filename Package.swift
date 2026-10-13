// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PortScope",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PortScope", targets: ["PortScope"])
    ],
    targets: [
        .executableTarget(
            name: "PortScope",
            path: "Sources/PortScope",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
