// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodedogCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CodedogCore", targets: ["CodedogCore"]),
    ],
    targets: [
        .target(name: "CodedogCore"),
        .testTarget(name: "CodedogCoreTests", dependencies: ["CodedogCore"]),
    ]
)
