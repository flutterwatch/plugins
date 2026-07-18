# firebase_auth_watchos — porting report

Scaffolded by `flutter-watchos plugin port --from-pub firebase_auth
--include-example` on 2026-07-17, then hand-finished.

Source: `firebase_auth` 6.5.6
Base platform: ios (Objective-C)
Model: **dart:ffi over the Firebase Apple SDK** (`FirebaseAuth`)

## Verification status

| Aspect | Status |
|---|---|
| Implementation (Dart + FFI + native) | ✅ complete for watch-viable flows |
| watchOS capability | ◐ email/anonymous/token sign-in work; provider/OAuth, phone, and MFA flows need UI the watch cannot present |
| Host unit tests | ✅ 13/13 pass (native FirebaseAuth faked) |
| On-simulator build + link + run | ✅ links the Firebase Apple SDK; smoke test passes against the real Auth backend |
| Physical watch hardware | ○ not yet verified |
| Upstream integration test | ○ none in the firebase_auth pub example (smoke test added) |

## Async bridge over FFI

Auth operations are network-backed, so unlike this repo's synchronous FFI
plugins the native layer runs them asynchronously: Dart calls
`firebase_auth_watchos_begin` with a JSON request (`{"op": ..., "app": ...}`
plus arguments) and receives a token, then polls
`firebase_auth_watchos_poll(token)` until the SDK completion replaces
`{"pending": true}` with the result. Auth-state streams follow the repo's
poll-a-generation pattern: the native layer registers the SDK's
auth-state/ID-token listeners once per app and bumps counters that
`firebase_auth_watchos_current_user` reports alongside the user snapshot;
`authStateChanges`/`idTokenChanges`/`userChanges` poll the counters and emit
on change (the poll timer stops when the subscription is cancelled).

Errors carry FlutterFire's string codes: the native layer reads the SDK's
`FIRAuthErrorUserInfoNameKey` (`ERROR_WRONG_PASSWORD`) and converts it to the
FlutterFire form (`wrong-password`), which the Dart side rethrows as
`FirebaseAuthException`.

## Links an external native SDK

Like `firebase_core_watchos`, `watchos/Package.swift` declares the Firebase
Apple SDK as a SwiftPM dependency (product `FirebaseAuth`); the
`flutter-watchos` CLI builds the package with xcodebuild's SwiftPM for the
active watch SDK, harvests the resulting objects, and force-loads them into
Runner. System frameworks/libraries: `Foundation`, `Security`, `libz`,
`libc++` (`SystemConfiguration` is **not** linked — it does not exist on
watchOS).

## APIs the source plugin used that do not exist on watchOS

| API | Why / watchOS note |
|---|---|
| UIApplication (`FLTFirebaseAuthPlugin.m`) | Used for provider/OAuth redirect flows; no watchOS equivalent — those flows are unsupported here. |
| UIKit views (`FLTFirebaseAuthPlugin.m`) | Used to present reCAPTCHA/OAuth view controllers; the Flutter watchOS embedder owns the whole screen and plugins cannot present native view controllers. |

## What is implemented

- `watchos/Classes/firebase_auth_watchos_ffi.{h,m}` — the async begin/poll
  bridge plus synchronous current-user/sign-out/language-code/emulator/
  email-link-check symbols over `FIRAuth`/`FIRUser`. Results are JSON.
- `lib/firebase_auth_watchos.dart` — `FirebaseAuthWatchos extends
  FirebaseAuthPlatform`, `UserWatchos extends UserPlatform`,
  `UserCredentialWatchos`, `MultiFactorWatchos`, over the FFI bindings.
- `test/firebase_auth_watchos_test.dart` — host tests with the native backend
  faked (13/13).
- `example/` — the upstream firebase_auth example, ported for watchOS, plus
  an added `integration_test/firebase_auth_smoke_test.dart` (the pub example
  ships no upstream integration_test).
