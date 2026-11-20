# permission_handler_example

`permission_handler_apple`'s own example app, on watchOS: it lists every
permission with its status and asks for one when tapped. Run it, and its
integration test, on an Apple Watch simulator with:

```sh
flutter-watchos run -d <watch-sim>
flutter-watchos test integration_test/permission_handler_test.dart -d <watch-sim>
```

Two of the test's cases depend on location, and each skips itself unless
location is as it needs. The Simulator keeps a location answer across
installs, so set it before each run:

```sh
xcrun simctl privacy <watch-sim> reset location com.example.permissionHandlerExample.watchkitapp
flutter-watchos test integration_test/permission_handler_test.dart -d <watch-sim>
xcrun simctl privacy <watch-sim> grant location com.example.permissionHandlerExample.watchkitapp
flutter-watchos test integration_test/permission_handler_test.dart -d <watch-sim>
```
