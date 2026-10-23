## 0.2.0

* **Breaking:** works with `firebase_storage` 14.x, and needs it. The package
  now depends on `firebase_core: ^5.0.0` (was `^4.0.0`) and
  `firebase_storage_platform_interface: ^6.0.8` (was `^6.0.3`), the first
  version of the platform interface for `firebase_core` 5.x. An app that stays
  on `firebase_storage` 13.x keeps 0.1.1.
* The watch still links the Firebase Apple SDK 11.x through
  `watchos/Package.swift`. The move to SDK 13 in `firebase_storage` 14.0.0 is
  for its iOS and macOS code.
* The platform interface's one change in 6.0.9, an error snapshot of a
  method-channel task that keeps the metadata of the snapshot before it, is
  in code this package does not use. A watchOS task snapshot carries metadata
  only when an upload succeeds, as before.
* `firebase_storage` 14.0.1 keeps the custom metadata of a data URL upload.
  `putString` passes the metadata it is given to the native upload, and a new
  test checks that the custom metadata arrives.
* README: the install snippet names `firebase_core: ^5.1.0`,
  `firebase_storage: ^14.0.1` and this version.
* Example: `pubspec.yaml` names `firebase_storage: ^14.0.1` and
  `firebase_core: ^5.1.0`. No native code changed, and the example was not
  rebuilt on the Simulator for this version.

## 0.1.1

* API docs and comments say "release" for handing native memory back.
* Example: `pubspec.yaml` names `firebase_storage: ^13.6.0` instead of `any`.

## 0.1.0

* Released with flutter-watchos 0.1.0. The code is the same as in the last
  published build.
* The watchOS implementation of `firebase_storage`: a dart:ffi bridge over
  the Firebase Apple SDK (`FirebaseStorage`) implementing references (delete,
  download URLs, metadata, `list` and `listAll`), data transfer (`getData`,
  `putData`, `putString`, `putFile`, `writeToFile`) with native task progress
  (snapshot events, pause, resume and cancel), and instance configuration
  (emulator, retry times).
* Scaffolded with `flutter-watchos plugin port`, then finished by hand.
* Links the Firebase Apple SDK through the CLI's support for external SwiftPM
  dependencies.
* Checked on the watchOS 27.0 Simulator: the example builds and starts, and
  the host unit tests pass. Not yet run on a physical Apple Watch.
