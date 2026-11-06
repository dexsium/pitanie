// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "watch_ancs",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "watch-ancs", targets: ["watch_ancs"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "watch_ancs",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
