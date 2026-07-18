# firebase_messaging_watchos — porting report

Scaffolded by `flutter-watchos plugin port --from-pub firebase_messaging
--include-example` on 2026-07-18, then hand-finished.

Source: `firebase_messaging` 16.4.3
Base platform: ios (Objective-C)
Model: **dart:ffi over the Firebase Apple SDK** (`FirebaseMessaging`)

## Verification status

| Aspect | Status |
|---|---|
| Implementation (Dart + FFI + native) | ✅ complete (background handler is a no-op — see below) |
| watchOS capability | ✅ FirebaseMessaging is source-built and watch-capable |
| Host unit tests | ✅ 15/15 pass (native FirebaseMessaging faked) |
| On-simulator build + link + run | ✅ links the Firebase Apple SDK; smoke test passes |
| Physical watch hardware | ○ not yet verified |
| Upstream integration test | ○ none in the firebase_messaging pub example (smoke test added) |

## APNs on watchOS — the app-delegate bridge

The one iOS API with no drop-in watchOS equivalent was `UIApplication`, which
FlutterFire uses to register for remote notifications and to receive the APNs
device token + notification payloads. On watchOS those callbacks are delivered
only to an app-level `WKApplicationDelegate` — and `UNUserNotificationCenter`
has a single process-global delegate slot no plugin should claim for itself.

Both are owned by the `flutter-watchos` runner's `FlutterWatchOSAppDelegate`,
which rebroadcasts every callback (`didRegisterForRemoteNotifications`,
`didFailToRegister…`, `didReceiveRemoteNotification`, plus the notification
center's `willPresent`/`didReceiveResponse`) as `NSNotification`s. This plugin
observes them by name (no compile-time dependency on the runner), hands the
APNs token to `FIRMessaging`, queues received payloads (deduplicated by
message id — a notification+`content-available` push arrives via two
callbacks), and answers the foreground-presentation query through a mutable
options box in the notification's userInfo. Callbacks that fire before the
plugin's first FFI call (an at-launch token, the launching tap) are buffered
by the runner and replayed once the plugin posts its observers-ready
notification. Apps adopt the delegate with a one-liner (current templates
include it automatically):

```swift
@WKApplicationDelegateAdaptor(FlutterWatchOSAppDelegate.self)
private var flutterAppDelegate
```

## Async bridge over FFI

- **Token/topic/permission calls** are network-backed and use the same
  begin/poll token pattern as the other `firebase_*_watchos` packages.
- **Received messages** queue natively (foreground → `onMessage`, tap →
  `onMessageOpenedApp`, launch tap → `getInitialMessage`); a Dart pump drains
  the queues into the platform-interface's broadcast stream controllers.
- **`onTokenRefresh`** polls a native token-generation counter (the SDK's
  `FIRMessagingDelegate` bumps it) and emits the new FCM token on change.

`registerBackgroundMessageHandler` is a no-op: watchOS has no background
isolate to run a Dart handler in. `setDeliveryMetricsExportToBigQuery` is
Android/web only.

Notification settings are mapped from the watchOS-safe subset of
`UNNotificationSettings` (authorization/alert/sound/notificationCenter/critical,
plus announcement on watchOS 6+ and timeSensitive on watchOS 8+); badge,
CarPlay, lock screen, and previews are reported as `notSupported`.

## Links an external native SDK

Like the other `firebase_*_watchos` packages, `watchos/Package.swift` declares
the Firebase Apple SDK as a SwiftPM dependency (product `FirebaseMessaging`);
the `flutter-watchos` CLI builds the package with xcodebuild's SwiftPM, harvests
the resulting objects (deduplicating the shared FirebaseCore/GoogleUtilities
objects against other Firebase plugins), and force-loads them into Runner.
System frameworks/libraries: `Foundation`, `Security`, `WatchKit`,
`UserNotifications`, `libz`, `libc++`.

## What is implemented

- `watchos/Classes/firebase_messaging_watchos_ffi.{h,m}` — begin/poll ops
  (permission, settings, token, topics), a token/APNs state reader, native
  message queues, and synchronous configuration (register for remote
  notifications, foreground presentation, auto-init), plus the
  `UNUserNotificationCenter`/`FIRMessaging` delegates and the app-delegate
  notification observers.
- `lib/firebase_messaging_watchos.dart` — `FirebaseMessagingWatchos extends
  FirebaseMessagingPlatform` with the message pump feeding
  `onMessage`/`onMessageOpenedApp`, over the FFI bindings.
- `test/firebase_messaging_watchos_test.dart` — host tests with the native
  backend faked (15/15).
- `example/` — the upstream firebase_messaging example, ported for watchOS
  (runner refreshed to the host-module model so the app-delegate adaptor is
  available), plus an added `integration_test/firebase_messaging_smoke_test.dart`
  (the pub example ships no upstream integration_test).
