# firebase_storage_watchos — porting report

Scaffolded by `flutter-watchos plugin port --from-pub firebase_storage
--include-example` on 2026-07-17, then hand-finished.

Source: `firebase_storage` 13.4.5
Base platform: ios (Swift)
Model: **dart:ffi over the Firebase Apple SDK** (`FirebaseStorage`)

## Verification status

| Aspect | Status |
|---|---|
| Implementation (Dart + FFI + native) | ✅ complete (putBlob is web-only) |
| watchOS capability | ✅ FirebaseStorage is source-built and watch-capable |
| Host unit tests | ✅ 14/14 pass (native FirebaseStorage faked) |
| On-simulator build + link + run | ✅ links the Firebase Apple SDK; smoke test passes |
| Physical watch hardware | ○ not yet verified |
| Upstream integration test | ○ none in the firebase_storage pub example (smoke test added) |

## Async bridge over FFI

Storage operations are network-backed, so the native layer runs them
asynchronously in two shapes:

- **One-shot operations** (delete, download URL, metadata, list, getData)
  use the same begin/poll token pattern as `firebase_auth_watchos`.
- **Uploads/downloads** run as native SDK tasks
  (`firebase_storage_watchos_task_start`): the native layer attaches the
  SDK's status observers (progress/pause/resume/success/failure) and keeps a
  latest-snapshot dict per task that
  `firebase_storage_watchos_task_snapshot` reports; the Dart `TaskWatchos`
  polls it for `snapshotEvents`/`onComplete` (the poll timer stops on
  cancel/terminal state), and pause/resume/cancel forward synchronously.

Bytes cross the bridge base64-encoded inside the JSON payloads — fine at
watch-app scale.

Errors carry FlutterFire's string codes: the native layer maps the SDK's
stable `FIRStorageErrorDomain` raw codes (e.g. -13010) to the FlutterFire
form (`object-not-found`), which the Dart side rethrows as
`FirebaseException(plugin: 'firebase_storage')`.

## Links an external native SDK

Like the other `firebase_*_watchos` packages, `watchos/Package.swift`
declares the Firebase Apple SDK as a SwiftPM dependency (product
`FirebaseStorage`); the `flutter-watchos` CLI builds the package with
xcodebuild's SwiftPM, harvests the resulting objects (deduplicating the
shared FirebaseCore/GoogleUtilities objects against other Firebase plugins),
and force-loads them into Runner. System frameworks/libraries: `Foundation`,
`Security`, `libz`, `libc++`.

## What is implemented

- `watchos/Classes/firebase_storage_watchos_ffi.{h,m}` — begin/poll one-shot
  ops, task start/snapshot/control, and synchronous configuration
  (emulator, retry times) over `FIRStorage`/`FIRStorageReference`.
- `lib/firebase_storage_watchos.dart` — `FirebaseStorageWatchos extends
  FirebaseStoragePlatform`, `ReferenceWatchos`, `TaskWatchos`,
  `TaskSnapshotWatchos`, `ListResultWatchos`, over the FFI bindings.
- `test/firebase_storage_watchos_test.dart` — host tests with the native
  backend faked (14/14).
- `example/` — the upstream firebase_storage example, ported for watchOS,
  plus an added `integration_test/firebase_storage_smoke_test.dart` (the pub
  example ships no upstream integration_test).
