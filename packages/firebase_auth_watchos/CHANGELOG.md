## 0.1.0

* Released with flutter-watchos 0.1.0. The code is the same as in the last
  published build.
* The watchOS implementation of `firebase_auth`: a dart:ffi bridge over the
  Firebase Apple SDK (`FirebaseAuth`) implementing the sign-in flows a watch
  can run (anonymous, email/password, email link, custom token), the
  current-user snapshot and the `authStateChanges`, `idTokenChanges` and
  `userChanges` streams, user management (ID tokens, profile updates,
  verification emails, password updates, delete), and password-reset and
  action-code handling.
* Provider/OAuth sign-in, phone auth and multi-factor flows are not
  supported: they need UI the watch cannot present.
  `User.reauthenticateWithCredential`, `User.linkWithCredential`,
  `User.unlink`, `sendSignInLinkToEmail`, `checkActionCode` and
  `setSettings` are not implemented yet.
* Scaffolded with `flutter-watchos plugin port`, then finished by hand.
* Links the Firebase Apple SDK through the CLI's support for external SwiftPM
  dependencies.
* Checked on the watchOS 27.0 Simulator: the example builds and starts, and
  the host unit tests pass. Not yet run on a physical Apple Watch.
