# flutter_local_notifications_watchos

The watchOS implementation of [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications).

Notifications go through **UserNotifications** (`UNUserNotificationCenter`)
over dart:ffi: show one now, schedule one for a date (once or repeating), or
repeat one every interval; list, cancel, and get taps back.

> Scaffolded by [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
> from `flutter_local_notifications`, then implemented and verified by hand.

## Usage

This is a federated plugin implementation. Apps that already depend on
`flutter_local_notifications` and target watchOS only need to add this
package alongside it:

```yaml
dependencies:
  flutter_local_notifications: ^22.3.2
  flutter_local_notifications_watchos: ^0.0.1
```

The plugin registers automatically via Flutter's federated registry — no
explicit imports required from app code. The watch reports itself as iOS,
so pass `iOS:` settings and details, as on an iPhone:

```dart
await FlutterLocalNotificationsPlugin().initialize(
  settings: const InitializationSettings(iOS: DarwinInitializationSettings()),
  onDidReceiveNotificationResponse: (NotificationResponse r) => print(r.payload),
);
```

The app must install the flutter-watchos host's application delegate,
which owns the notification-center delegate and forwards its callbacks;
`flutter-watchos create` does (`@WKApplicationDelegateAdaptor(FlutterWatchOSAppDelegate.self)`
in `watchos/Runner/App.swift`), and the CLI warns at build time when it is
missing.

## Behaviour on watchOS

| Member | watchOS |
|---|---|
| `initialize` | supported: categories with their actions, default presentation, the permissions the settings request |
| `requestPermissions` / `checkPermissions` | supported; `isBadgeEnabled` is always false: watchOS has no badge setting |
| `show` | supported |
| `zonedSchedule` | supported: a calendar trigger in the date's own time zone, repeating by `matchDateTimeComponents` |
| `periodicallyShow` / `periodicallyShowWithDuration` | supported: a repeating interval trigger |
| `cancel` / `cancelAll` / `cancelAllPendingNotifications` | supported |
| `pendingNotificationRequests` / `getActiveNotifications` | supported, for this package's notifications |
| `getNotificationAppLaunchDetails` | supported: the tap that launched the app |
| `onDidReceiveNotificationResponse` | taps and action taps, with the notification's id and payload |

Of `DarwinNotificationDetails`, these reach the notification: the five
`present…` flags (for a notification arriving while the app is in front),
`subtitle`, `threadIdentifier`, `categoryIdentifier`, `badgeNumber`,
`interruptionLevel` and `attachments`.

## Not supported on watchOS

| Member | On watchOS | Why |
|---|---|---|
| `DarwinNotificationDetails.sound` | the default sound plays instead | watchOS has no `UNNotificationSound soundNamed:` |
| `DarwinNotificationAction.text` | a plain action; `NotificationResponse.input` is null | the host's delegate forwards the action, not the typed text |
| `onDidReceiveBackgroundNotificationResponse` | not called; every tap reaches `onDidReceiveNotificationResponse` | the watch app handles taps in its own isolate |
| `openAppNotificationSettings` | returns false | watchOS has no settings page an app can open |

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
