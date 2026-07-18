## 0.0.1-beta.1

* Initial watchOS implementation of `firebase_messaging`: a dart:ffi bridge
  over the Firebase Apple SDK (`FirebaseMessaging`) implementing tokens
  (`getToken`, `getAPNSToken`, `deleteToken`, `onTokenRefresh`), permissions
  (`requestPermission`, `getNotificationSettings` mapped to the watchOS-safe
  `UNNotificationSettings` subset), messages (`onMessage`,
  `onMessageOpenedApp`, `getInitialMessage`), topics
  (`subscribeToTopic`/`unsubscribeFromTopic`), and presentation/auto-init
  configuration.
* Receives the APNs device token and notification payloads through the
  `flutter-watchos` runner's `FlutterWatchOSAppDelegate`
  (`@WKApplicationDelegateAdaptor`), the only path watchOS exposes for
  remote notifications.
* `registerBackgroundMessageHandler` is a no-op (watchOS has no background
  isolate); `setDeliveryMetricsExportToBigQuery` is Android/web only.
* Scaffolded with `flutter-watchos plugin port`, then hand-finished.
* Links the Firebase Apple SDK via the CLI's external-SwiftPM-dependency
  support. Verified on the watch simulator: host unit tests (15/15) and an
  on-simulator smoke test. Not yet verified on physical watch hardware;
  published as a pre-release.
