// swift-tools-version:5.9
// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// FFI plugin manifest. The flutter-watchos CLI discovers the plugin through
// this file, compiles `Classes/*.m` into a static archive force-loaded into
// the watch binary, and links the frameworks and libraries declared below.
import PackageDescription

let package = Package(
    name: "sqflite_watchos",
    platforms: [
        .watchOS("7.0"),
    ],
    products: [
        .library(name: "sqflite-watchos", targets: ["sqflite_watchos"]),
    ],
    targets: [
        .target(
            name: "sqflite_watchos",
            path: "Classes",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                // The system SQLite, whose C API Dart calls directly.
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
