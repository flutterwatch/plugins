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

## Not supported on watchOS

These members of `network_info_plus_platform_interface` 3.1.0 throw or fail on watchOS.
`PORTING_REPORT.md` lists every member under "Interface coverage".

| Member | On watchOS | Why |
|---|---|---|
| `getWifiName` / `getWifiBSSID` | always null | watchOS has no CaptiveNetwork or NEHotspotNetwork |
| `getWifiGatewayIP` | always null | watchOS has no routing-table API |

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
