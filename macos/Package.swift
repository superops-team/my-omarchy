// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyOmarchy",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "my-omarchy", targets: ["MyOmarchy"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "0.12.0"),
    ],
    targets: [
        .executableTarget(name: "MyOmarchy"),
        .testTarget(
            name: "MyOmarchyTests",
            dependencies: [
                "MyOmarchy",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
