# firebase_messaging_watchos

The watchOS implementation of [`firebase_messaging`](https://pub.dev/packages/firebase_messaging).

Bridges the **Firebase Apple SDK** (`FirebaseMessaging`) to Flutter on watchOS
over `dart:ffi`. Method-channel plugins are not supported on watchOS, so this
package exports C symbols from
`watchos/Classes/firebase_messaging_watchos_ffi.m` that wrap `FIRMessaging`;
`watchos/Package.swift` declares a SwiftPM dependency on
[`firebase-ios-sdk`](https://github.com/firebase/firebase-ios-sdk)'s
`FirebaseMessaging` product, and Dart resolves the symbols via
`DynamicLibrary.process()`. Token and topic calls use an async begin/poll
bridge; received messages queue natively and a Dart pump drains them into the
platform interface's `onMessage` / `onMessageOpenedApp` streams.

> Firebase support on watchOS is new.
>
> **What has been checked:** the example app builds and starts on the
> watchOS 27.0 Simulator, and the host unit tests pass. The Simulator run
> was with 0.1.1 and `firebase_messaging` 16.x; 0.2.0 changes no native code,
> and its example has not been rebuilt yet. It has not yet been run on a
> physical Apple Watch.
>
> Requires `firebase_core_watchos` (the initialization + app registry
> foundation) and a `flutter-watchos` CLI with external-SwiftPM-dependency
> linking.

## APNs on watchOS

Firebase Cloud Messaging needs the APNs device token, which watchOS delivers
only through the app-level `WKApplicationDelegate`. The `flutter-watchos`
runner ships a `FlutterWatchOSAppDelegate` that owns the notification
delegates and rebroadcasts the remote-notification and user-notification
callbacks to plugins; adopt it in your `App`:

```swift
@WKApplicationDelegateAdaptor(FlutterWatchOSAppDelegate.self)
private var flutterAppDelegate
```

Apps created with a current `flutter-watchos` template already include this.
Add `remote-notification` to `UIBackgroundModes` and the push entitlement to
receive messages on device. The watch Simulator has no APNs environment, so
there `getToken` fails with `[firebase_messaging/unknown]` ("No APNS token
specified before fetching FCM Token").

## Implemented surface

- Tokens: `getToken`, `getAPNSToken`, `deleteToken`, `onTokenRefresh`.
- Permissions: `requestPermission`, `getNotificationSettings` (mapped to the
  watchOS-safe subset of `UNNotificationSettings`; capabilities the watch
  lacks — badge, CarPlay, lock screen and the setting for showing message
  content — report `notSupported`).
- Messages: `onMessage`, `onMessageOpenedApp`, `getInitialMessage`.
- Topics: `subscribeToTopic`, `unsubscribeFromTopic`.
- Presentation & init: `setForegroundNotificationPresentationOptions`,
  `setAutoInitEnabled` / `isAutoInitEnabled`.

`registerBackgroundMessageHandler` is a no-op — watchOS has no background
isolate to run a handler in — and `setDeliveryMetricsExportToBigQuery` is
Android/web only.

## Usage

This is a federated plugin implementation. Apps that already depend on
`firebase_messaging` and target watchOS add this package (and the
`firebase_core_watchos` foundation) alongside it:

```yaml
dependencies:
  firebase_core: ^5.1.0
  firebase_core_watchos: ^0.1.2
  firebase_messaging: ^17.0.1
  firebase_messaging_watchos: ^0.2.0
```

Version 0.2.0 needs `firebase_messaging` 17.x and `firebase_core` 5.x. An app
that stays on `firebase_messaging` 16.x uses 0.1.1.

Then use `firebase_messaging`'s API exactly as on iOS — the watchOS
implementation registers automatically via Flutter's federated plugin runner.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the
full text. Firebase itself is © Google under the Apache-2.0 license.
