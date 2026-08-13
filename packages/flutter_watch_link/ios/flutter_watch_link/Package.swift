// swift-tools-version: 5.9

// The iPhone half, for Swift Package Manager consumers. CocoaPods consumers get
// the same code through ../flutter_watch_link.podspec; both compile a one-line
// shim that includes ../../src.
//
// `type: .dynamic` is load-bearing, not a style choice. This plugin's C symbols
// exist purely for dart:ffi to look up at runtime, so nothing in the app
// references them — and a static library's members are only pulled in when
// something does. Built statically it links cleanly and produces an app with
// none of the symbols in it, failing at first use instead of at build time.

import PackageDescription

let package = Package(
    name: "flutter_watch_link",
    platforms: [
        .iOS("12.0"),
    ],
    products: [
        .library(
            name: "flutter-watch-link",
            type: .dynamic,
            targets: ["flutter_watch_link"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "flutter_watch_link",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("WatchConnectivity")
            ]
        )
    ]
)
