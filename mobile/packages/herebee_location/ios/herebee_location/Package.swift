// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "herebee_location",
    platforms: [
        // Must match the podspec and the app; CoreLocation APIs used here
        // (authorizationStatus, accuracyAuthorization) need iOS 14+.
        .iOS("16.0")
    ],
    products: [
        .library(name: "herebee-location", targets: ["herebee_location"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "herebee_location",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // Declares no tracking and no collected data types. Apple reads
                // this at submission, so it ships with the plugin.
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
