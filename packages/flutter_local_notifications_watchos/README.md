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
| `getNotificationAppLaunchDetails` | supported: the tap that launched the app. A launch tap that comes in only after this was asked is not lost: it reaches `onDidReceiveNotificationResponse` once `initialize` has run |
| `onDidReceiveNotificationResponse` | taps and action taps, with the notification's id and payload; background actions too, since the watch app has no background isolate, and dismissals of notifications whose details set `dismissIsolate`. A banner shown while the app is in front closes when tapped and sends no response: watchOS does not report that tap |

Of `DarwinNotificationDetails`, these reach the notification: the
`present…` flags (for a notification arriving while the app is in front;
`presentBanner` and `presentList` decide, and `presentAlert` is not read, as
on iOS 14 and later), `subtitle`, `threadIdentifier`, `categoryIdentifier`,
`badgeNumber`, `interruptionLevel`, `criticalSoundVolume`, `dismissIsolate`
and `attachments`.

`InterruptionLevel.timeSensitive` needs the Time Sensitive Notifications
capability (`com.apple.developer.usernotifications.time-sensitive`) in the
watch app's entitlements, and critical alerts, `requestCriticalPermission`
and `criticalSoundVolume` need the Critical Alerts entitlement
(`com.apple.developer.usernotifications.critical-alerts`), which Apple grants
on request.

`flutter_timezone` has no watchOS implementation, so `tz.local` stays UTC on
the watch unless the app sets it: pass `zonedSchedule` a `TZDateTime` in the
zone you mean, for example from `tz.getLocation('Europe/Istanbul')`.

## Not supported on watchOS

| Member | On watchOS | Why |
|---|---|---|
| `DarwinNotificationDetails.sound` | the default sound plays instead | watchOS has no `UNNotificationSound soundNamed:` |
| `DarwinNotificationAction.text` | a plain action; `NotificationResponse.input` is null | the host's delegate forwards the action, not the typed text |
| `onDidReceiveBackgroundNotificationResponse` | not called; every tap reaches `onDidReceiveNotificationResponse` | the watch app handles taps in its own isolate |
| `openAppNotificationSettings` | returns false | watchOS has no settings page an app can open |

## Following upstream

This class extends upstream's concrete `IOSFlutterLocalNotificationsPlugin`,
as flutter_local_notifications requires on iOS-reporting platforms. A method
an upstream release adds to that class, a minor release included, reaches
its method channel here and throws `MissingPluginException` until this
package overrides it too. 23.0.0 is in development.

## License

BSD-3-Clause, as upstream flutter_local_notifications: `LICENSE` carries
Michael Bui's notice and The FlutterWatch Authors'. See `LICENSE` for the
full text.
