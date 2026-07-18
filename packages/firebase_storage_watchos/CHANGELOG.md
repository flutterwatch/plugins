## 0.0.1-beta.1

* Initial watchOS implementation of `firebase_storage`: a dart:ffi bridge
  over the Firebase Apple SDK (`FirebaseStorage`) implementing references
  (delete, download URLs, metadata, list/listAll), data transfer (`getData`,
  `putData`/`putString`/`putFile`, `writeToFile`) with native task progress
  (snapshot events, pause/resume/cancel), and instance configuration
  (emulator, retry times).
* Scaffolded with `flutter-watchos plugin port`, then hand-finished.
* Links the Firebase Apple SDK via the CLI's external-SwiftPM-dependency
  support. Verified on the watch simulator: host unit tests (14/14) and an
  on-simulator smoke test against the real Storage backend.
  Not yet verified on physical watch hardware; published as a pre-release.
