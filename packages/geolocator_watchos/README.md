# geolocator_watchos

The watchOS implementation of [`geolocator`](https://pub.dev/packages/geolocator).

Location comes from **CoreLocation** (`CLLocationManager`) over dart:ffi: the
delegate caches the latest fix and **pushes** a signal into Dart. The position
stream, `getCurrentPosition` and `requestPermission` all wait on it — nothing
polls.

> Scaffolded by [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
> from `geolocator_apple`, then implemented and verified by hand.

## Usage

This is a federated plugin implementation. Apps that already depend on
`geolocator` and target watchOS only need to add this package alongside it:

```yaml
dependencies:
  geolocator: ^<latest>
  geolocator_watchos: ^0.0.1
```

The plugin registers automatically via Flutter's federated registry — no
explicit imports required from app code.

Add a location usage description to the watch app's `Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Explain why your app needs location.</string>
```

## Behaviour on watchOS

| Method | watchOS |
|---|---|
| `checkPermission` / `requestPermission` | supported (when-in-use) |
| `isLocationServiceEnabled` | supported |
| `getCurrentPosition` / `getPositionStream` | supported |
| `getLastKnownPosition` | supported (last cached fix) |
| `openAppSettings` / `openLocationSettings` | not available on watchOS |
| `getServiceStatusStream` | not implemented |

The watch has no *Always* background-location entitlement flow that iOS has;
authorization is when-in-use.

## Status

| Platform | Implemented |
|----------|-------------|
| Apple Watch (`watchos`) | yes |
| Watch simulator (`watchsimulator`) | query methods verified; live fixes need a simulated location |

The example is geolocator's own upstream Baseflow demo, ported verbatim. That
demo ships no `integration_test/`, so this package is verified by building and
running the example on the watch simulator; the interactive permission prompt
and live position updates are verified on a physical Apple Watch.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
