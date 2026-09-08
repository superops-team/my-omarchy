// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyOmarchy",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "my-omarchy", targets: ["MyOmarchy"]),
    ],
    targets: [
        .executableTarget(name: "MyOmarchy"),
        .testTarget(name: "MyOmarchyTests", dependencies: ["MyOmarchy"]),
    ],
    swiftLanguageModes: [.v5]
)
