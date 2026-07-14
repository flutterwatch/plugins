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
  network_info_plus: ^<latest>
  network_info_plus_watchos: ^0.0.1
```

The plugin registers automatically via Flutter's federated registry — no
explicit imports required from app code.

## Behaviour on watchOS

| Getter | watchOS |
|---|---|
| `getWifiIP` / `getWifiIPv6` | supported (active interface, preferring `en0`) |
| `getWifiSubmask` / `getWifiBroadcast` | supported |
| `getWifiName` (SSID) / `getWifiBSSID` | **null** — watchOS has no CaptiveNetwork / NEHotspotNetwork |
| `getWifiGatewayIP` | unimplemented (no watchOS routing-table API) |

## Status

| Platform | Implemented |
|----------|-------------|
| Apple Watch (`watchos`) | yes (addressing only) |
| Watch simulator (`watchsimulator`) | yes |

Verified end-to-end on the watch simulator (`example/integration_test`).

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
