// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Terry",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "Terry", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "TerryTests", dependencies: ["Terry"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
