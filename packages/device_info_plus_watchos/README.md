# device_info_plus_watchos

The watchOS implementation of [`device_info_plus`](https://pub.dev/packages/device_info_plus).

Scaffolded with [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
and finished by hand as an **FFI** implementation over `WKInterfaceDevice` —
see `PORTING_REPORT.md`.

## Usage

```yaml
dependencies:
  device_info_plus: ^11.0.0
  device_info_plus_watchos: ^0.1.0
```

watchOS reports as an iOS-family platform, so read it through the iOS
accessor:

```dart
final info = await DeviceInfoPlugin().iosInfo;
print(info.systemVersion); // watchOS version, e.g. "11.0"
print(info.utsname.machine); // e.g. "Watch7,1"
```

## API coverage

Populates the `IosDeviceInfo` fields from `WKInterfaceDevice`, `uname()`,
`NSProcessInfo`, and `NSFileManager`:

| Field | Source |
|---|---|
| `name`, `systemName`, `systemVersion`, `model`, `localizedModel` | `WKInterfaceDevice` |
| `identifierForVendor` | `WKInterfaceDevice.identifierForVendor` |
| `utsname.*`, `modelName` | `uname()` (machine id, e.g. `Watch7,1`) |
| `physicalRamSize` / `availableRamSize` | `NSProcessInfo.physicalMemory` |
| `freeDiskSize` / `totalDiskSize` | `NSFileManager` filesystem attributes |
| `isPhysicalDevice` | `TARGET_OS_SIMULATOR` |
| `isiOSAppOnMac` / `isiOSAppOnVision` | always false (impossible on a watch) |

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
