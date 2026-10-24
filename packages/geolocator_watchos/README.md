# geolocator_watchos

The watchOS implementation of [`geolocator`](https://pub.dev/packages/geolocator).

Location comes from **CoreLocation** (`CLLocationManager`) over dart:ffi: the
delegate caches the latest fix and **pushes** a signal into Dart. The position
stream, `getCurrentPosition` and `requestPermission` all wait on it — nothing
polls. As in geolocator_apple, the position stream and `getCurrentPosition`
each have a location manager of their own.

> Scaffolded by [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
> from `geolocator_apple`, then implemented and verified by hand.

## Usage

This is a federated plugin implementation. Apps that already depend on
`geolocator` and target watchOS only need to add this package alongside it:

```yaml
dependencies:
  geolocator: ^14.1.1
  geolocator_watchos: ^0.2.0
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
| `getCurrentPosition` | supported; skips cached fixes more than 5 seconds old, and does not wait on a running stream |
| `getPositionStream` | supported; while a stream runs, a second call gets it, with its settings, as from geolocator_apple |
| `getLastKnownPosition` | supported (last cached fix) |
| `getLocationAccuracy` | supported (precise or reduced) |
| `requestTemporaryFullAccuracy` | supported; needs `NSLocationTemporaryUsageDescriptionDictionary` |
| `getServiceStatusStream` | supported; starts with the current status |

The watch has no *Always* background-location entitlement flow that iOS has;
authorization is when-in-use.

### Workouts and background updates

`AppleSettings` from `geolocator`, passed to `getPositionStream`, reaches
CoreLocation here too: `activityType` sets `CLLocationManager.activityType`,
and `allowBackgroundLocationUpdates`, which `AppleSettings` turns on by
default, sets `allowsBackgroundLocationUpdates`. A running or cycling app
passes `ActivityType.fitness`:

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
App Review accepts background location only for a feature that needs it
(App Review Guideline 2.5.4); say what it is for in the usage description.

`pauseLocationUpdatesAutomatically` and `showBackgroundLocationIndicator` do
not exist on watchOS and are ignored. `ActivityType.maritime` needs the
watchOS 27 SDK and watchOS 27; otherwise it is `otherNavigation`, as in
geolocator_apple. An app recording a workout keeps running with the wrist
down through its `HKWorkoutSession`, not through this setting.

Not yet checked on a physical watch: the temporary full-accuracy prompt, and
updates with the wrist down.

## Status

| Platform | Implemented |
|----------|-------------|
| Apple Watch (`watchos`) | yes |
| Watch simulator (`watchsimulator`) | query methods verified; live fixes need a simulated location |

The interactive permission prompt and live position updates are verified on
a physical Apple Watch.

## Example

The example is `geolocator`'s own example app, the Baseflow demo, ported with
`flutter-watchos plugin port --include-example`. Its code is unchanged; these
are its watchOS deviations:

| Where | Change | Why |
|---|---|---|
| `example/pubspec.yaml` | adds `url_launcher_watchos: ^0.1.1` | the Baseflow template opens its links with `url_launcher`, which needs it to open them on the watch |
| `example/watchos/Runner/Info.plist` | sets `FlutterWatchOSContentScale` to `0.6` | the demo is designed for a phone and overflowed the watch screen by 106 pixels on a 46 mm Simulator; the scale lays it out in a logical space 1.67 times the screen's size and draws it smaller, without touching the Dart code |

The demo ships no `integration_test/`, so this package is verified by building
and running the example on the watch simulator.

## Not supported on watchOS

These members of `geolocator_platform_interface` 4.4.0 throw or fail on watchOS.
`PORTING_REPORT.md` lists every member under "Interface coverage".

| Member | On watchOS | Why |
|---|---|---|
| `openAppSettings` / `openLocationSettings` | fail with `UnimplementedError` | watchOS has no settings page an app can open |

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
