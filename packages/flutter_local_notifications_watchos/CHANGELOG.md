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
  launch tap is not missed.
* The example's `lib/` is a small watch demo, because the upstream example
  needs `flutter_timezone`; its official integration test is upstream's,
  unchanged.
