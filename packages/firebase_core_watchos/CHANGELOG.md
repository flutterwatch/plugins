## 0.1.1

* API docs and comments say "release" for handing native memory back.
* Example: `pubspec.yaml` names `firebase_core: ^4.15.0` instead of `any`.

## 0.1.0

* Released with flutter-watchos 0.1.0. The code is the same as in the last
  published build.
* The watchOS implementation of `firebase_core`: a dart:ffi bridge over the
  Firebase Apple SDK (`FirebaseCore`) implementing `Firebase.initializeApp`
  (default and named apps, from `FirebaseOptions` or a bundled
  `GoogleService-Info.plist`), the app registry (`Firebase.apps`,
  `Firebase.app`), and per-app options, automatic data collection and delete.
* Scaffolded with `flutter-watchos plugin port`, then finished by hand.
* Links the Firebase Apple SDK through the CLI's support for external SwiftPM
  dependencies.
* Checked on the watchOS 27.0 Simulator: the example builds and starts, the
  host unit tests pass, and the smoke test initializes the default app and a
  named app. Not yet run on a physical Apple Watch.
