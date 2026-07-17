## 0.0.1-beta.1

* Initial watchOS implementation of `firebase_core`: a dart:ffi bridge over the
  Firebase Apple SDK (`FirebaseCore`) implementing `Firebase.initializeApp`
  (default + named apps, from `FirebaseOptions` or a bundled
  `GoogleService-Info.plist`), the app registry (`Firebase.apps`/`app`), and
  per-app options, automatic-data-collection, and delete.
* Scaffolded with `flutter-watchos plugin port`, then hand-finished.
* Pre-release: on-device linking is pending `flutter-watchos` toolchain support
  for resolving external SwiftPM package dependencies. Host unit tests pass;
  see PORTING_REPORT.md.
