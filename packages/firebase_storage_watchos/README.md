# firebase_storage_watchos

The watchOS implementation of [`firebase_storage`](https://pub.dev/packages/firebase_storage).

Bridges the **Firebase Apple SDK** (`FirebaseStorage`) to Flutter on watchOS
over `dart:ffi`. Method-channel plugins are not supported on watchOS, so this
package exports C symbols from `watchos/Classes/firebase_storage_watchos_ffi.m`
that wrap `FIRStorage`/`FIRStorageReference`; `watchos/Package.swift` declares
a SwiftPM dependency on
[`firebase-ios-sdk`](https://github.com/firebase/firebase-ios-sdk)'s
`FirebaseStorage` product, and Dart resolves the symbols via
`DynamicLibrary.process()`. One-shot operations use an async begin/poll
bridge; uploads and downloads run as native SDK tasks whose progress
snapshots the Dart side polls.

> **Experimental.** Firebase support on watchOS is new. This package builds,
> links the Firebase Apple SDK, and passes its host tests and an on-simulator
> smoke test, but has not yet been proven on physical watch hardware; it is
> published as a pre-release.
>
> Requires `firebase_core_watchos` (the initialization + app registry
> foundation) and a `flutter-watchos` CLI with external-SwiftPM-dependency
> linking.

## Implemented surface

- References: `ref`, `child`/`parent`/`root` plumbing, `delete`,
  `getDownloadURL`, `getMetadata`, `updateMetadata`, `list`, `listAll`.
- Data: `getData`, `putData`, `putString`, `putFile`, `writeToFile`.
- Tasks: `snapshotEvents`, `snapshot`, `onComplete`, `pause`, `resume`,
  `cancel`, with upload/download progress.
- Configuration: `useStorageEmulator`, `setMaxOperationRetryTime`,
  `setMaxUploadRetryTime`, `setMaxDownloadRetryTime`.

`putBlob` is web-only and reports unsupported.

## Usage

This is a federated plugin implementation. Apps that already depend on
`firebase_storage` and target watchOS add this package (and the
`firebase_core_watchos` foundation) alongside it:

```yaml
dependencies:
  firebase_core: ^4.0.0
  firebase_core_watchos: ^0.0.1-beta.1
  firebase_storage: ^13.0.0
  firebase_storage_watchos: ^0.0.1-beta.1
```

Then use `firebase_storage`'s API exactly as on iOS — the watchOS
implementation registers automatically via Flutter's federated plugin runner.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the
full text. Firebase itself is © Google under the Apache-2.0 license.
