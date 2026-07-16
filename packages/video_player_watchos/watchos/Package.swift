// swift-tools-version:5.9
// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// FFI plugin manifest. The flutter-watchos CLI discovers the plugin through
// this file, compiles `Classes/*.m` (and the SwiftUI platform-view sources in
// `Views/`) into a static archive force-loaded into the watch binary, and
// links the frameworks declared below.
import PackageDescription

let package = Package(
    name: "video_player_watchos",
    platforms: [
        .watchOS("7.0"),
    ],
    products: [
        .library(name: "video-player-watchos", targets: ["video_player_watchos"]),
    ],
    targets: [
        .target(
            name: "video_player_watchos",
            path: "Classes",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("SwiftUI"),
            ]
        ),
    ]
)
