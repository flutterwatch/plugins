# battery_plus_watchos

The watchOS implementation of [`battery_plus`](https://pub.dev/packages/battery_plus).

Scaffolded with [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
and finished by hand as an **FFI** implementation over `WKInterfaceDevice` —
see `PORTING_REPORT.md`.

## Usage

```yaml
dependencies:
  battery_plus: ^6.0.0
  battery_plus_watchos: ^0.1.0
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

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
