# firebase_core_watchos — porting report

Scaffolded by `flutter-watchos plugin port --from-pub firebase_core
--include-example` on 2026-07-17, then hand-finished.

Source: `firebase_core` 4.12.1. Since 0.1.2 also read against `firebase_core`
5.1.0, which uses the same `firebase_core_platform_interface` 8.x. The watch
still links the Firebase Apple SDK 11.x (`watchos/Package.resolved` pins
11.15.0); the newer SDK that `firebase_core` 5.x uses on iOS and macOS does
not apply to it.
Base platform: ios (Objective-C)
Model: **dart:ffi over the Firebase Apple SDK** (`FirebaseCore`)

## Verification status

| Aspect | Status |
|---|---|
| Implementation (Dart + FFI + native) | ✅ complete |
| watchOS capability | ◐ FirebaseCore supports watchOS 8+; SPM manifest allows `.watchOS(.v7)` |
| Host unit tests | ✅ 8/8 pass (native FirebaseCore faked) |
| On-simulator build + link + run | ✅ links the Firebase Apple SDK; smoke test passes (with `firebase_core` 4.x; the example has not been rebuilt with 5.x) |
| Physical watch hardware | ○ not yet verified |
| Upstream integration test | ○ none in the firebase_core pub example (smoke test added) |

## Links an external native SDK (the first in this repo)

Unlike every other package in this repo, `firebase_core_watchos` links an
**external native SDK** (the Firebase Apple SDK), not just system frameworks.
`watchos/Package.swift` declares that dependency the SwiftPM way:

```swift
.package(url: "https://github.com/firebase/firebase-ios-sdk.git", .upToNextMajor(from: "11.0.0")),
// target dependency: .product(name: "FirebaseCore", package: "firebase-ios-sdk")
```

The `flutter-watchos` CLI supports this: when a plugin's `Package.swift`
declares an external SwiftPM package, the CLI builds that package with
xcodebuild's SwiftPM for the active watch SDK (compiling the plugin's `.m`
with the `FirebaseCore` module available), harvests every resulting object
(the plugin plus `FirebaseCore`, `FirebaseCoreInternal`, `GoogleUtilities`,
…), and force-loads them into Runner — force-load being required anyway so the
SDK's `+load` component registration and the FFI exports survive. The system
frameworks/libraries the SDK needs are declared via `.linkedFramework` /
`.linkedLibrary` in the plugin manifest (`Security`, `libz`, `libc++`;
`SystemConfiguration` is **not** linked — it does not exist on watchOS).

## What is implemented

- `watchos/Classes/firebase_core_watchos_ffi.{h,m}` — C symbols wrapping
  `FIRApp`/`FIROptions`: configure (default + named), read options, list apps,
  delete, set automatic data collection. Results are returned as JSON.
- `lib/firebase_core_watchos.dart` — `FirebaseCoreWatchos extends
  FirebasePlatform` + `FirebaseAppWatchos extends FirebaseAppPlatform`, over
  the FFI bindings.
- `test/firebase_core_watchos_test.dart` — host tests with the native backend
  faked (8/8).
- `example/` — the upstream firebase_core example, ported for watchOS.
