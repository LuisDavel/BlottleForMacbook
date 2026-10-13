// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Blottle",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BlottleKit", targets: ["BlottleKit"]),
        .executable(name: "blottle", targets: ["blottle"]),
        .executable(name: "BlottleApp", targets: ["BlottleApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "BlottleKit",
            path: "Sources/BlottleKit"
        ),
        .executableTarget(
            name: "blottle",
            dependencies: [
                "BlottleKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/blottle"
        ),
        .executableTarget(
            name: "BlottleApp",
            dependencies: ["BlottleKit"],
            path: "Sources/BlottleApp"
        ),
        .testTarget(
            name: "BlottleKitTests",
            dependencies: ["BlottleKit"],
            path: "Tests/BlottleKitTests"
        ),
    ]
)
