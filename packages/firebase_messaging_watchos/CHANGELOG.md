## 0.2.0

* **Breaking:** works with `firebase_messaging` 17.x, and needs it. The
  package now depends on `firebase_core: ^5.0.0` (was `^4.0.0`) and
  `firebase_messaging_platform_interface: ^4.11.0` (was `^4.9.0`), the first
  version of the platform interface for `firebase_core` 5.x. An app that
  stays on `firebase_messaging` 16.x keeps 0.1.1.
* The watch still links the Firebase Apple SDK 11.x through
  `watchos/Package.swift`. The move to SDK 13 in `firebase_messaging` 17.0.0
  is for its iOS and macOS code.
* README: the install snippet names `firebase_core: ^5.1.0`,
  `firebase_messaging: ^17.0.1` and this version.
* Example: `pubspec.yaml` names `firebase_messaging: ^17.0.1` and
  `firebase_core: ^5.1.0`. Its code is unchanged and still calls `getToken`
  and `onTokenRefresh`. No native code changed, and the example was not
  rebuilt on the Simulator for this version.

## 0.1.1

* API docs and comments say "release" for handing native memory back.
* Example: the notification settings screen calls the message-content
  setting "Message Content".
* Example: `pubspec.yaml` names `firebase_messaging: ^16.7.0` instead of `any`.

## 0.1.0

* Released with flutter-watchos 0.1.0. The code is the same as in the last
  published build.
* The watchOS implementation of `firebase_messaging`: a dart:ffi bridge over
  the Firebase Apple SDK (`FirebaseMessaging`) implementing tokens
  (`getToken`, `getAPNSToken`, `deleteToken`, `onTokenRefresh`), permissions
  (`requestPermission`, and `getNotificationSettings` mapped to the subset of
  `UNNotificationSettings` that watchOS has), messages (`onMessage`,
  `onMessageOpenedApp`, `getInitialMessage`), topics (`subscribeToTopic`,
  `unsubscribeFromTopic`), and presentation and auto-init settings.
* Receives the APNs device token and notification payloads through the
  `flutter-watchos` runner's `FlutterWatchOSAppDelegate`
  (`@WKApplicationDelegateAdaptor`), the only path watchOS offers for remote
  notifications.
* `registerBackgroundMessageHandler` is a no-op (watchOS has no background
  isolate); `setDeliveryMetricsExportToBigQuery` is Android and web only.
* Scaffolded with `flutter-watchos plugin port`, then finished by hand.
* Links the Firebase Apple SDK through the CLI's support for external SwiftPM
  dependencies.
* Checked on the watchOS 27.0 Simulator: the example builds and starts, and
  the host unit tests pass. Not yet run on a physical Apple Watch.
