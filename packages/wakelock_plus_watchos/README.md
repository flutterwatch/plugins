# wakelock_plus_watchos

The watchOS implementation of [`wakelock_plus`](https://pub.dev/packages/wakelock_plus).

watchOS has no idle timer an app can turn off, so here the wakelock is an
**extended runtime session** (`WKExtendedRuntimeSession`) over dart:ffi:
while it runs, the app keeps running and comes back to the front with the
wrist down. `enable()` starts one and completes once it runs; `disable()`
ends it; `enabled` says whether one is running.

> Scaffolded by [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
> from `wakelock_plus`, then implemented and verified by hand.

## Usage

This is a federated plugin implementation. Apps that already depend on
`wakelock_plus` and target watchOS only need to add this package alongside it:

```yaml
dependencies:
  wakelock_plus: ^1.8.1
  wakelock_plus_watchos: ^0.0.1
```

The plugin registers automatically via Flutter's federated registry — no
explicit imports required from app code.

The session's type comes from the watch app's `Info.plist`. Name the one
that fits the app; App Review checks that it does:

```xml
<key>WKBackgroundModes</key>
<array>
	<string>self-care</string>
</array>
```

`self-care` sessions last up to 10 minutes; `mindfulness` and
`physical-therapy` up to an hour; `alarm` is for smart alarms. A workout app
does not need this: its `HKWorkoutSession` keeps it running (see
[`flutter_watch_workout`](../flutter_watch_workout)).

## Behaviour on watchOS

| Member | watchOS |
|---|---|
| `toggle(enable: true)` / `enable()` | starts a session and completes once it runs |
| `toggle(enable: false)` / `disable()` | ends the session; `enabled` reads false at once |
| `enabled` | whether a session is running |

- Without a session type in `WKBackgroundModes`, `enable()` completes and
  `enabled` stays false: there is nothing on watchOS to start.
- When the system refuses the session, `enable()` fails with a
  `PlatformException` with code `session_invalidated` and the
  `WKExtendedRuntimeSessionErrorCode` as `details`; error 7 means the
  `Info.plist` lacks the session type the app is approved for.
- A session ends on its own when its type's time is up; `enabled` then
  reads false, and `enable()` starts a new one.
- The screen still dims to Always On with the wrist down: a session keeps the
  app in front, not the display bright.

## Not supported on watchOS

Nothing: every member of `wakelock_plus_platform_interface` 1.7.0 is
implemented, with the session model above in place of an idle timer.
`PORTING_REPORT.md` lists each member under "Interface coverage".

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
