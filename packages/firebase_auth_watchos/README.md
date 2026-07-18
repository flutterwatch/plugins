# firebase_auth_watchos

The watchOS implementation of [`firebase_auth`](https://pub.dev/packages/firebase_auth).

Bridges the **Firebase Apple SDK** (`FirebaseAuth`) to Flutter on watchOS over
`dart:ffi`. Method-channel plugins are not supported on watchOS, so this
package exports C symbols from `watchos/Classes/firebase_auth_watchos_ffi.m`
that wrap `FIRAuth`/`FIRUser`; `watchos/Package.swift` declares a SwiftPM
dependency on [`firebase-ios-sdk`](https://github.com/firebase/firebase-ios-sdk)'s
`FirebaseAuth` product, and Dart resolves the symbols via
`DynamicLibrary.process()`. Auth calls are network-backed, so the bridge is
asynchronous: Dart starts a native operation and polls for its completion,
and the auth-state streams poll the SDK's change notifications.

> **Experimental.** Firebase support on watchOS is new. This package builds,
> links the Firebase Apple SDK, and passes its host tests and an on-simulator
> smoke test, but has not yet been proven on physical watch hardware; it is
> published as a pre-release.
>
> Requires `firebase_core_watchos` (the initialization + app registry
> foundation) and a `flutter-watchos` CLI with external-SwiftPM-dependency
> linking.

## Implemented surface

Sign-in flows a watch can actually run — no browser or OAuth UI exists on
watchOS:

- `signInAnonymously`, `signInWithEmailAndPassword`,
  `createUserWithEmailAndPassword`, `signInWithEmailLink`,
  `signInWithCustomToken`, and `signInWithCredential` for email credentials.
- `currentUser`, `authStateChanges`, `idTokenChanges`, `userChanges`,
  `signOut`.
- `User.getIdToken` / `getIdTokenResult`, `reload`, `delete`,
  `updateProfile`, `updatePassword`, `sendEmailVerification`,
  `verifyBeforeUpdateEmail`.
- `sendPasswordResetEmail`, `confirmPasswordReset`,
  `verifyPasswordResetCode`, `applyActionCode`.
- `setLanguageCode`, `useAuthEmulator`, `isSignInWithEmailLink`.

**Not supported** (they require UI flows or hardware the watch cannot
present): provider/OAuth sign-in (`signInWithProvider`, popup/redirect),
phone-number authentication, reCAPTCHA verification, and multi-factor
enrollment. These throw `UnimplementedError` or report `unimplemented`.

## Usage

This is a federated plugin implementation. Apps that already depend on
`firebase_auth` and target watchOS add this package (and the
`firebase_core_watchos` foundation) alongside it:

```yaml
dependencies:
  firebase_core: ^4.0.0
  firebase_core_watchos: ^0.0.1-beta.1
  firebase_auth: ^6.0.0
  firebase_auth_watchos: ^0.0.1-beta.1
```

Then use `firebase_auth`'s API exactly as on iOS — the watchOS implementation
registers automatically via Flutter's federated plugin runner.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the
full text. Firebase itself is © Google under the Apache-2.0 license.
