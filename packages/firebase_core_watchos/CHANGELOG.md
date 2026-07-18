## 0.0.1-beta.1

* Initial watchOS implementation of `firebase_core`: a dart:ffi bridge over the
  Firebase Apple SDK (`FirebaseCore`) implementing `Firebase.initializeApp`
  (default + named apps, from `FirebaseOptions` or a bundled
  `GoogleService-Info.plist`), the app registry (`Firebase.apps`/`app`), and
  per-app options, automatic-data-collection, and delete.
* Scaffolded with `flutter-watchos plugin port`, then hand-finished.
* Links the Firebase Apple SDK via the CLI's external-SwiftPM-dependency
  support. Verified on the watch simulator: host unit tests (8/8) and an
  on-simulator smoke test that initializes the default and a named app.
  Not yet verified on physical watch hardware; published as a pre-release.
