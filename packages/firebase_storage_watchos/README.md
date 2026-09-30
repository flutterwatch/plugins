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

> Firebase support on watchOS is new.
>
> **What has been checked:** the example app builds and starts on the
> watchOS 27.0 Simulator, and the host unit tests pass. It has not yet been
> run on a physical Apple Watch.
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
  firebase_core_watchos: ^0.1.0
  firebase_storage: ^13.0.0
  firebase_storage_watchos: ^0.1.0
```

Then use `firebase_storage`'s API exactly as on iOS — the watchOS
implementation registers automatically via Flutter's federated plugin runner.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the
full text. Firebase itself is © Google under the Apache-2.0 license.
