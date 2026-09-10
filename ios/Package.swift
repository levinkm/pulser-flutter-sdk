// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "pulser_sdk",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(name: "pulser-sdk", targets: ["pulser_sdk"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "pulser_sdk",
            dependencies: [],
            path: "Classes",
            resources: [],
            publicHeadersPath: "include",
            cSettings: [],
            swiftSettings: [],
            linkerSettings: []
        )
    ]
)
