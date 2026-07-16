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

The upstream integration suites are included verbatim, along with the
upstream `server/` fixture server they expect. Start the server, then run
the suite against it (the watch simulator shares the host's network, so
`localhost` reaches the server):

```sh
dart run server/bin/server.dart &
flutter-watchos drive --driver=test_driver/integration_test.dart \
  --target=integration_test/lib_test.dart \
  --dart-define=USE_LOCAL_SERVER=true -d <watch-sim>
```

Without `USE_LOCAL_SERVER` the test data plays remote URLs instead; note
that upstream's remote host is missing some fixtures (e.g. the
special-character file), so the hermetic local-server run is the one that
matches upstream CI. The runner's `Info.plist` carries upstream's
`NSAllowsArbitraryLoads` so cleartext HTTP to the local server works.
