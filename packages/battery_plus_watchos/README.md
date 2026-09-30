# battery_plus_watchos

The watchOS implementation of [`battery_plus`](https://pub.dev/packages/battery_plus).

Scaffolded with [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
and finished by hand as an **FFI** implementation over `WKInterfaceDevice` —
see `PORTING_REPORT.md`.

## Usage

`battery_plus` does not include a watchOS implementation, so add this
package alongside it:

```yaml
dependencies:
  battery_plus: ^7.1.1
  battery_plus_watchos: ^0.1.1
```

```dart
final battery = Battery();
print(await battery.batteryLevel);       // 0–100
print(await battery.batteryState);       // charging / full / discharging
```

## API coverage

| Member | watchOS |
|---|---|
| `batteryLevel` | ✅ `WKInterfaceDevice.batteryLevel` (monitoring auto-enabled) |
| `batteryState` | ✅ `WKInterfaceDevice.batteryState` |
| `isInBatterySaveMode` | ✅ `NSProcessInfo.isLowPowerModeEnabled` (watchOS 9+, else false) |
| `onBatteryStateChanged` | ✅ poll-based — watchOS has no battery-change notification, so the stream polls every `BatteryPlusWatchos.pollInterval` (default 2s) and emits on change |

## Example on the watch screen

The example is `battery_plus`'s own example app, kept verbatim. It is
designed for a phone and overflows a watch screen at native density, so the
example's runner opts into the flutter-watchos content scale
(`watchos/Runner/Info.plist`):

```xml
<key>FlutterWatchOSContentScale</key>
<real>0.4</real>
```

The app lays out in a logical space 2.5 times the screen's size and is drawn
smaller, without touching the example's Dart code. The watchOS widget test
`example/test/watchos_content_scale_test.dart` lays the app out at that scale
on every watch screen size and fails on any overflow.

## Not supported on watchOS

Nothing: every member of `battery_plus_platform_interface` 2.0.1 is implemented.
`batteryLevel` fails with an `Exception` while watchOS reports no level (-1), which some Simulators do.
`PORTING_REPORT.md` lists each member under "Interface coverage".

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
