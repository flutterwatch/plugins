// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "b_watchos",
    dependencies: [.package(url: "https://example.com/sdk.git", from: "1.0.0")],
    targets: [.target(name: "b_watchos", path: "Classes")]
)
