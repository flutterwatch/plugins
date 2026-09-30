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
