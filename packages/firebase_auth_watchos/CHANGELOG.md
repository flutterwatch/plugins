## 0.2.0

* **Breaking:** works with `firebase_auth` 7.x, and needs it. The package now
  depends on `firebase_core: ^5.0.0` (was `^4.0.0`) and
  `firebase_auth_platform_interface: ^9.1.1` (was `^9.0.5`), the first
  version of the platform interface for `firebase_core` 5.x. An app that
  stays on `firebase_auth` 6.x keeps 0.1.1.
* The watch still links the Firebase Apple SDK 11.x through
  `watchos/Package.swift`. The move to SDK 13 in `firebase_auth` 7.0.0 is
  for its iOS and macOS code.
* `authStateChanges`, `idTokenChanges` and `userChanges` no longer repeat
  their first value. The SDK calls each of its listeners once when the plugin
  installs them, on the first native call for an app, so with 0.1.1 a stream
  subscribed before any other auth call could emit the current user, or null,
  a second time. As in `firebase_auth`, the streams now leave that call out.
* The same streams report a signed-out state once, as `firebase_auth` 7.0.1
  does: a null is not emitted when the last value emitted was null too.
* `User.updateProfile`: `firebase_auth` 7.0.1 passes only the fields it is
  given, so an omitted field now keeps its value on the watch; this package
  already applied only the fields present in the request. A field given as
  `null` is forwarded to the SDK's profile change request. The Firebase Apple
  SDK then clears it on the local user and does not send it to the server, as
  on iOS. A new test checks that the `null` reaches the native layer.
* README: the install snippet names `firebase_core: ^5.1.0`,
  `firebase_auth: ^7.0.1` and this version. "Not implemented yet" now lists
  the `ActionCodeSettings` that `sendPasswordResetEmail`,
  `sendEmailVerification` and `verifyBeforeUpdateEmail` do not pass on.
* Example: `pubspec.yaml` names `firebase_auth: ^7.0.1`,
  `firebase_core: ^5.1.0` and `firebase_messaging: ^17.0.1`. No native code
  changed, and the example was not rebuilt on the Simulator for this version.

## 0.1.1

* API docs and comments say "release" for handing native memory back.
* Example: `pubspec.yaml` names `firebase_auth: ^6.7.0` instead of `any`.

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
