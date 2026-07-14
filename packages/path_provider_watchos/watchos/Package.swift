// swift-tools-version:5.9
// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// FFI plugin manifest. The flutter-watchos CLI discovers the plugin through
// this file, compiles `Classes/*.m` into a static archive force-loaded into
// the watch binary, and links the frameworks declared below.

import PackageDescription

let package = Package(
    name: "path_provider_watchos",
    platforms: [
        .watchOS(.v7),
    ],
    products: [
        .library(name: "path-provider-watchos", targets: ["path_provider_watchos"]),
    ],
    targets: [
        .target(
            name: "path_provider_watchos",
            path: "Classes",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
            ]
        ),
    ]
)
