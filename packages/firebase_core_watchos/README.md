# firebase_core_watchos

The watchOS implementation of [`firebase_core`](https://pub.dev/packages/firebase_core).

Bridges the **Firebase Apple SDK** (`FirebaseCore`) to Flutter on watchOS over
`dart:ffi`. Method-channel plugins are not supported on watchOS, so this
package exports C symbols from `watchos/Classes/firebase_core_watchos_ffi.m`
that wrap `FIRApp`/`FIROptions`; `watchos/Package.swift` declares a SwiftPM
dependency on [`firebase-ios-sdk`](https://github.com/firebase/firebase-ios-sdk)'s
`FirebaseCore` product, and Dart resolves the symbols via
`DynamicLibrary.process()`.

> **Experimental — not yet runnable on device.** The Dart, FFI, and native
> layers are complete and host-tested, but linking the Firebase Apple SDK into
> a watch binary needs the `flutter-watchos` toolchain to resolve external
> SwiftPM package dependencies for plugins (today it links system frameworks
> only). Until that lands, this package builds and passes its host unit tests
> but cannot be linked into a watch app. See `PORTING_REPORT.md`.

## Requirements (once toolchain support lands)

- FirebaseCore requires **watchOS 8+** at runtime — set your app's
  `WATCHOS_DEPLOYMENT_TARGET` to `8.0` or higher.
- A Firebase configuration: either pass `FirebaseOptions` to
  `Firebase.initializeApp(options: ...)`, or bundle a `GoogleService-Info.plist`
  and call `Firebase.initializeApp()` with no options.

## Implemented surface

- `Firebase.initializeApp()` — default app (from options or a bundled plist)
  and named secondary apps.
- `Firebase.apps`, `Firebase.app([name])` — the app registry, read from the
  native SDK.
- `FirebaseApp.options`, `FirebaseApp.name`.
- `FirebaseApp.setAutomaticDataCollectionEnabled` /
  `isAutomaticDataCollectionEnabled`, `FirebaseApp.delete`.

`setAutomaticResourceManagementEnabled` is a no-op (watchOS has no equivalent
background-resource toggle).

## Usage

This is a federated plugin implementation. Apps that already depend on
`firebase_core` and target watchOS add this package alongside it:

```yaml
dependencies:
  firebase_core: ^4.0.0
  firebase_core_watchos: ^0.0.1-beta.1
```

Then use `firebase_core`'s API exactly as on iOS — the watchOS implementation
registers automatically via Flutter's federated plugin runner.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the
full text. Firebase itself is © Google under the Apache-2.0 license.
