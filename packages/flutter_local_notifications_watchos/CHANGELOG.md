## 0.0.1

First version, staged: checked on the watchOS 27.0 Simulator, not yet on a
physical watch.

* `FlutterLocalNotificationsWatchos` extends `IOSFlutterLocalNotificationsPlugin`,
  which flutter_local_notifications requires on iOS-reporting platforms, and
  answers every method through UNUserNotificationCenter over dart:ffi:
  initialize with categories, permissions, show, zonedSchedule (calendar
  triggers in the date's own time zone), periodicallyShow and
  periodicallyShowWithDuration, cancel, pending and delivered lists, and the
  launch tap.
* Taps reach `onDidReceiveNotificationResponse` through the flutter-watchos
  host's application delegate, observed from a load-time constructor so the
  launch tap is not missed. As upstream, only a tap on the notification or
  on an action that opens the app is the launch tap, and a dismissal is
  reported only for a notification whose details set `dismissIsolate`;
  background actions and those dismissals reach
  `onDidReceiveNotificationResponse`, since the watch has no background
  isolate.
* As upstream 22.3.2, an error in `UNErrorDomain` from adding a request is
  ignored: watchOS 27, like iOS 27, reports a missing permission that way.
* As upstream on iOS 14 and later, `presentAlert` is not read: the banner
  and the list have flags of their own. `checkPermissions` reports
  provisional authorization apart from `isEnabled`, and `initialize` answers
  false when it asks for nothing.
* `providesAppNotificationSettings` is asked for and reported;
  `criticalSoundVolume` plays the default critical sound at that volume.
* LICENSE carries Michael Bui's notice, as upstream's does.
* `DarwinNotificationDetails` without attachments no longer ends the app:
  their null reached native as NSNull, which it walked as a list.
* As upstream, an error from asking for permission is not reported; the
  answer is whether it was granted.
* The example's "With actions" buttons schedule a notification with an
  action that opens the app, a background action, and a reported
  dismissal, or one without it.
* The example's `lib/` is a small watch demo, because the upstream example
  needs `flutter_timezone`; its official integration test is upstream's,
  unchanged.
