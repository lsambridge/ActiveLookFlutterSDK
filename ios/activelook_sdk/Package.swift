// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "activelook_sdk",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "activelook-sdk", targets: ["activelook_sdk"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // ActiveLook's official iOS SDK — not on the Swift Package Index, resolved directly
        // from its GitHub tag per docs/plan-race-mode-activelook-glasses.md §7.4/§13.3.
        .package(url: "https://github.com/ActiveLook/ios-sdk.git", exact: "4.5.5"),
    ],
    targets: [
        .target(
            name: "activelook_sdk",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "ActiveLookSDK", package: "ios-sdk"),
            ],
            resources: [
                // If your plugin requires a privacy manifest, for example if it uses any required
                // reason APIs, update the PrivacyInfo.xcprivacy file to describe your plugin's
                // privacy impact, and then uncomment these lines. For more information, see
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                // .process("PrivacyInfo.xcprivacy"),

                // If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ]
        )
    ]
)
