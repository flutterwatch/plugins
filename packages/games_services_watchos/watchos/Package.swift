// swift-tools-version:5.9
//
// FFI plugin manifest. The flutter-watchos CLI discovers the plugin here,
// compiles Classes/*.m into a static archive force-loaded into the watch
// binary, and links the frameworks below.
import PackageDescription

let package = Package(
    name: "games_services_watchos",
    platforms: [.watchOS(.v7)],   // GKLeaderboard.submitScore is watchOS 7+
    products: [
        .library(name: "games-services-watchos", targets: ["games_services_watchos"]),
    ],
    targets: [
        .target(
            name: "games_services_watchos",
            path: "Classes",
            publicHeadersPath: ".",
            cSettings: [.headerSearchPath(".")],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("GameKit"),
            ]
        ),
    ]
)
