// swift-tools-version:5.9
// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
//
// The FFI manifest: what the CLI compiles into the watch binary.
import PackageDescription

let package = Package(
    name: "permission_handler_watchos",
    // The microphone and the full-access and write-only calendar prompts
    // are watchOS 10 APIs, and flutter-watchos apps target watchOS 26.
    platforms: [
        .watchOS("10.0"),
    ],
    products: [
        .library(name: "permission-handler-watchos", targets: ["permission_handler_watchos"]),
    ],
    targets: [
        .target(
            name: "permission_handler_watchos",
            path: "Classes",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("WatchKit"),
                // Notifications need no usage description, so they are the
                // one group linked. The other frameworks are loaded at
                // runtime, only when a permission of theirs is asked for.
                .linkedFramework("UserNotifications"),
            ]
        ),
    ]
)
