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

> **Experimental.** Firebase support on watchOS is new. This package builds,
> links the Firebase Apple SDK, and passes its host tests and an on-simulator
> smoke test, but has not yet been proven on physical watch hardware; it is
> published as a pre-release.
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
receive messages on device. The watch simulator has no APNs environment, so
`getToken` returns `null` there.

## Implemented surface

- Tokens: `getToken`, `getAPNSToken`, `deleteToken`, `onTokenRefresh`.
- Permissions: `requestPermission`, `getNotificationSettings` (mapped to the
  watchOS-safe subset of `UNNotificationSettings`; capabilities the watch
  lacks — badge, CarPlay, lock screen, previews — report `notSupported`).
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
  firebase_core: ^4.0.0
  firebase_core_watchos: ^0.0.1-beta.1
  firebase_messaging: ^15.0.0
  firebase_messaging_watchos: ^0.0.1-beta.1
```

Then use `firebase_messaging`'s API exactly as on iOS — the watchOS
implementation registers automatically via Flutter's federated plugin runner.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the
full text. Firebase itself is © Google under the Apache-2.0 license.
