// swift-tools-version:5.9
// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// FFI plugin manifest. The flutter-watchos CLI discovers the plugin through
// this file, compiles `Classes/*.m` into a static archive force-loaded into
// the watch binary, and resolves this SwiftPM graph — which pulls in the
// Firebase Apple SDK's `FirebaseMessaging` product (source-built; the SDK
// manifest supports `.watchOS(.v7)`). The Objective-C FFI layer imports
// `FirebaseMessaging` via its module and links it into the app.
import PackageDescription

let package = Package(
    name: "firebase_messaging_watchos",
    platforms: [
        .watchOS("7.0"),
    ],
    products: [
        .library(name: "firebase-messaging-watchos", targets: ["firebase_messaging_watchos"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk.git",
            .upToNextMajor(from: "11.0.0")
        ),
    ],
    targets: [
        .target(
            name: "firebase_messaging_watchos",
            dependencies: [
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),
            ],
            path: "Classes",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
            ],
            linkerSettings: [
                // The flutter-watchos CLI links these into Runner alongside
                // the harvested FirebaseMessaging/FirebaseCore/
                // GoogleUtilities objects. SystemConfiguration is
                // deliberately absent — it does not exist on watchOS.
                .linkedFramework("Foundation"),
                .linkedFramework("Security"),
                .linkedFramework("WatchKit"),
                .linkedFramework("UserNotifications"),
                .linkedLibrary("z"),
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
