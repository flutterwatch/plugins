# connectivity_plus_watchos

The watchOS implementation of [`connectivity_plus`](https://pub.dev/packages/connectivity_plus).

Scaffolded with [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
and finished by hand as an **FFI** implementation over the Network
framework's `NWPathMonitor` — see `PORTING_REPORT.md`.

## Usage

`connectivity_plus` does not include a watchOS implementation, so add this
package alongside it:

```yaml
dependencies:
  connectivity_plus: ^7.3.1
  connectivity_plus_watchos: ^0.2.1
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

The path monitor delivers its first path a moment after it starts. Until then
the value is unknown, and `checkConnectivity()` and a new listener's first
event wait for that first path, for at most one second, instead of reporting
`none`. If no path arrives within that second they report `none`, and the
stream sends the real value when it arrives.

`SCNetworkReachability` (which `connectivity_plus` uses on iOS) does not
exist on watchOS, so this uses the Network framework (watchOS 6+) instead.

## Example on the watch screen

The example is `connectivity_plus`'s own example app, kept verbatim. It is
designed for a phone and overflows a watch screen at native density, so the
example's runner opts into the flutter-watchos content scale
(`watchos/Runner/Info.plist`):

```xml
<key>FlutterWatchOSContentScale</key>
<real>0.5</real>
```

The app lays out in a logical space twice the screen's size and is drawn
smaller, without touching the example's Dart code. The watchOS widget test
`example/test/watchos_content_scale_test.dart` lays the app out at that scale
on every watch screen size and fails on any overflow.

## Not supported on watchOS

Nothing: every member of `connectivity_plus_platform_interface` 2.1.0 is implemented.
`PORTING_REPORT.md` lists each member under "Interface coverage".

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
