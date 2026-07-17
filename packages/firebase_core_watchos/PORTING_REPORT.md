# firebase_core_watchos — porting report

Scaffolded by `flutter-watchos plugin port --from-pub firebase_core
--include-example` on 2026-07-17, then hand-finished.

Source: `firebase_core` 4.12.1
Base platform: ios (Objective-C)
Model: **dart:ffi over the Firebase Apple SDK** (`FirebaseCore`)

## Verification status

| Aspect | Status |
|---|---|
| Implementation (Dart + FFI + native) | ✅ complete |
| watchOS capability | ◐ FirebaseCore supports watchOS 8+; SPM manifest allows `.watchOS(.v7)` |
| Host unit tests | ✅ 8/8 pass (native FirebaseCore faked) |
| On-device build / link | ✗ **blocked** — see below |
| Upstream integration test | ○ none in the firebase_core pub example |

## Blocked: the toolchain links system frameworks only

Unlike every other package in this repo, `firebase_core_watchos` links an
**external native SDK** (the Firebase Apple SDK), not just system frameworks.
`watchos/Package.swift` declares that dependency the SwiftPM way:

```swift
.package(url: "https://github.com/firebase/firebase-ios-sdk.git", .upToNextMajor(from: "11.0.0")),
// target dependency: .product(name: "FirebaseCore", package: "firebase-ios-sdk")
```

But the `flutter-watchos` build compiles each plugin's `watchos/Classes/*.m`
directly with `clang -fmodules` and force-loads the resulting static archive,
linking only the `.linkedFramework(...)` (system) frameworks it parses out of
`Package.swift`. It does **not** resolve a plugin's `.package(url:)` SwiftPM
dependencies. So `@import FirebaseCore;` fails with `module 'FirebaseCore' not
found`, and FirebaseCore's libraries are never linked.

Making this package (and any external-native-SDK plugin) build requires a
toolchain change: resolve a plugin's external SwiftPM package graph, put the
built modules on the plugin clang `-fmodules` search path, and link the
resulting static libraries (for FirebaseCore: `FirebaseCore`,
`FirebaseCoreInternal`, `GoogleUtilities`, `nanopb`, `FBLPromises`) into
Runner.

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
