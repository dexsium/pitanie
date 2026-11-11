// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "pitanie_native_ads",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "pitanie-native-ads", targets: ["pitanie_native_ads"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // Тот же SDK и версия, что у официального плагина yandex_mobileads.
        .package(
            url: "https://github.com/yandexmobile/yandex-ads-sdk-ios",
            .upToNextMinor(from: "8.6.0")
        ),
    ],
    targets: [
        .target(
            name: "pitanie_native_ads",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "YandexMobileAds", package: "yandex-ads-sdk-ios"),
            ]
        )
    ]
)
