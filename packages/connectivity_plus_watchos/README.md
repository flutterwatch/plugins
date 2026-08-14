# connectivity_plus_watchos

The watchOS implementation of [`connectivity_plus`](https://pub.dev/packages/connectivity_plus).

Scaffolded with [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
and finished by hand as an **FFI** implementation over the Network
framework's `NWPathMonitor` — see `PORTING_REPORT.md`.

## Usage

```yaml
dependencies:
  connectivity_plus: ^6.0.0
  connectivity_plus_watchos: ^0.1.0
```

```dart
final results = await Connectivity().checkConnectivity();
Connectivity().onConnectivityChanged.listen((r) => print(r));
```

## API coverage

| Member | watchOS |
|---|---|
| `checkConnectivity` | ✅ `NWPathMonitor` → wifi / mobile / ethernet / other / none |
| `onConnectivityChanged` | ✅ a persistent native `NWPathMonitor` **pushes** changes into Dart; no timer runs, and native suppresses updates that do not change the reported value |

`SCNetworkReachability` (which `connectivity_plus` uses on iOS) does not
exist on watchOS, so this uses the Network framework (watchOS 6+) instead.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
