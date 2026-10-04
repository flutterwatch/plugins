# network_info_plus_watchos

The watchOS implementation of [`network_info_plus`](https://pub.dev/packages/network_info_plus).

Interface addresses are read with `getifaddrs` over dart:ffi.

> Scaffolded by [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
> from `network_info_plus`, then implemented and verified by hand.

## Usage

This is a federated plugin implementation. Apps that already depend on
`network_info_plus` and target watchOS only need to add this package
alongside it:

```yaml
dependencies:
  network_info_plus: ^8.2.1
  network_info_plus_watchos: ^0.1.0
```

The plugin registers automatically via Flutter's federated registry — no
explicit imports required from app code.

## Behaviour on watchOS

| Getter | watchOS |
|---|---|
| `getWifiIP` / `getWifiIPv6` | supported (active interface, preferring `en0`) |
| `getWifiSubmask` / `getWifiBroadcast` | supported |

## Status

| Platform | Implemented |
|----------|-------------|
| Apple Watch (`watchos`) | yes (addressing only) |
| Watch simulator (`watchsimulator`) | yes |

Verified end-to-end on the watch simulator (`example/integration_test`).

## Example deviations

The example is `network_info_plus`'s own example app, and
`example/integration_test/network_info_plus_test.dart` is its official test,
both unchanged except for these watchOS deviations:

| Where | Change | Why |
|---|---|---|
| `example/lib/main.dart`, both permission requests | `Platform.isIOS` becomes `FlutterWatchosPlatform.isIos` | `Platform.isIOS` is true on the watch, and `permission_handler` has no watchOS implementation, so the request failed with `MissingPluginException` at start |
| `example/pubspec.yaml` | adds `flutter_watchos: ^0.1.0` | for `FlutterWatchosPlatform` |
| `example/watchos/Runner/Info.plist` | sets `FlutterWatchOSContentScale` to `0.4` | the app is designed for a phone and overflowed the watch screen (by 107 pixels on a 46 mm Simulator); the scale makes it lay out in a logical space 2.5 times the screen's size and draws it smaller, without touching the Dart code |

`example/integration_test/watchos_example_start_test.dart` is a watchOS test
beside the upstream one: it starts the example and checks that it shows its
network info without an error. The watchOS widget test
`example/test/watchos_content_scale_test.dart` lays the app out at its content
scale on every watch screen size, with a global IPv6 address on screen, and
fails on any overflow.

## Not supported on watchOS

These members of `network_info_plus_platform_interface` 3.1.0 throw or fail on watchOS.
`PORTING_REPORT.md` lists every member under "Interface coverage".

| Member | On watchOS | Why |
|---|---|---|
| `getWifiName` / `getWifiBSSID` | always null | watchOS has no CaptiveNetwork or NEHotspotNetwork |
| `getWifiGatewayIP` | always null | watchOS has no routing-table API |

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
