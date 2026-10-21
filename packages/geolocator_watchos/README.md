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
  geolocator: ^14.1.1
  geolocator_watchos: ^0.1.2
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
| `getLocationAccuracy` | supported (precise or reduced) |
| `requestTemporaryFullAccuracy` | supported; needs `NSLocationTemporaryUsageDescriptionDictionary` |
| `getServiceStatusStream` | supported; starts with the current status |

The watch has no *Always* background-location entitlement flow that iOS has;
authorization is when-in-use.

### Workouts and background updates

`AppleSettings` from `geolocator` reaches CoreLocation here too:
`activityType` sets `CLLocationManager.activityType`, and
`allowBackgroundLocationUpdates` sets `allowsBackgroundLocationUpdates`. A
running or cycling app passes `ActivityType.fitness`:

```dart
Geolocator.getPositionStream(
  locationSettings: AppleSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    activityType: ActivityType.fitness,
    allowBackgroundLocationUpdates: true,
  ),
);
```

Background updates turn on only when the `Info.plist`'s `UIBackgroundModes`
has `location`; without it the setting is ignored, because CoreLocation
asserts and the app ends otherwise. It has to be `UIBackgroundModes`, also on
the watch: `location` under `WKBackgroundModes` does not count and still
trips the assertion.

```xml
<key>UIBackgroundModes</key>
<array>
	<string>location</string>
</array>
```
`pauseLocationUpdatesAutomatically` and `showBackgroundLocationIndicator` do
not exist on watchOS and are ignored. An app recording a workout keeps
running with the wrist down through its `HKWorkoutSession`
([`flutter_watch_workout`](../flutter_watch_workout)), not through this
setting.

## Status

| Platform | Implemented |
|----------|-------------|
| Apple Watch (`watchos`) | yes |
| Watch simulator (`watchsimulator`) | query methods verified; live fixes need a simulated location |

The example is geolocator's own upstream Baseflow demo, ported verbatim. That
demo ships no `integration_test/`, so this package is verified by building and
running the example on the watch simulator; the interactive permission prompt
and live position updates are verified on a physical Apple Watch.

## Not supported on watchOS

These members of `geolocator_platform_interface` 4.4.0 throw or fail on watchOS.
`PORTING_REPORT.md` lists every member under "Interface coverage".

| Member | On watchOS | Why |
|---|---|---|
| `openAppSettings` / `openLocationSettings` | fail with `UnimplementedError` | watchOS has no settings page an app can open |

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
