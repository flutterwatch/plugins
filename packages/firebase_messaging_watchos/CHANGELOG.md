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
