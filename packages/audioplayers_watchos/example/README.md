# audioplayers_example

The **upstream `audioplayers` example app, verbatim**, with a watchOS runner.
Run it on an Apple Watch simulator with:

```sh
flutter-watchos run
```

## Example on the watch screen

The upstream UI is phone-designed (a multi-tab Material app) and does not
fit a watch screen at native density, so the runner opts into the
flutter-watchos content scale (`watchos/Runner/Info.plist`):

```xml
<key>FlutterWatchOSContentScale</key>
<real>0.5</real>
```

This lays the app out in a proportionally larger logical space rendered
smaller — same layout, smaller components — without touching the example's
Dart code.

## Integration tests

The upstream integration suites are included verbatim. Run them with:

```sh
flutter-watchos drive --driver=test_driver/integration_test.dart \
  --target=integration_test/lib_test.dart -d <watch-sim>
```

The default (no `USE_LOCAL_SERVER`) test data plays remote URLs, so the
simulator needs network access.
