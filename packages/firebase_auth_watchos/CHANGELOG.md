## 0.0.1-beta.1

* Initial watchOS implementation of `firebase_auth`: a dart:ffi bridge over
  the Firebase Apple SDK (`FirebaseAuth`) implementing the sign-in flows a
  watch can run (anonymous, email/password, email link, custom token), the
  current-user snapshot and `authStateChanges`/`idTokenChanges`/`userChanges`
  streams, user management (ID tokens, profile updates, verification emails,
  password updates, delete), and password-reset / action-code handling.
* Provider/OAuth sign-in, phone auth, and multi-factor flows are not
  supported — they need UI the watch cannot present.
* Scaffolded with `flutter-watchos plugin port`, then hand-finished.
* Links the Firebase Apple SDK via the CLI's external-SwiftPM-dependency
  support. Verified on the watch simulator: host unit tests (13/13) and an
  on-simulator smoke test against the real Firebase Auth backend.
  Not yet verified on physical watch hardware; published as a pre-release.
