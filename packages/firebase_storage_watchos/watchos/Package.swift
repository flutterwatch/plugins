// swift-tools-version:5.9
// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// FFI plugin manifest. The flutter-watchos CLI discovers the plugin through
// this file, compiles `Classes/*.m` into a static archive force-loaded into
// the watch binary, and resolves this SwiftPM graph — which pulls in the
// Firebase Apple SDK's `FirebaseStorage` product (source-built; the SDK
// manifest supports `.watchOS(.v7)`). The Objective-C FFI layer imports
// `FirebaseStorage` via its module and links it into the app.
import PackageDescription

let package = Package(
    name: "firebase_storage_watchos",
    platforms: [
        .watchOS("7.0"),
    ],
    products: [
        .library(name: "firebase-storage-watchos", targets: ["firebase_storage_watchos"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk.git",
            .upToNextMajor(from: "11.0.0")
        ),
    ],
    targets: [
        .target(
            name: "firebase_storage_watchos",
            dependencies: [
                .product(name: "FirebaseStorage", package: "firebase-ios-sdk"),
            ],
            path: "Classes",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
            ],
            linkerSettings: [
                // The flutter-watchos CLI links these into Runner alongside
                // the harvested FirebaseStorage/FirebaseCore/GoogleUtilities
                // objects. SystemConfiguration is deliberately absent — it
                // does not exist on watchOS.
                .linkedFramework("Foundation"),
                .linkedFramework("Security"),
                .linkedLibrary("z"),
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
