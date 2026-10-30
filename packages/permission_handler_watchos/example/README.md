# permission_handler_example

`permission_handler_apple`'s own example app, on watchOS: it lists every
permission with its status and asks for one when tapped. Run it, and its
integration test, on an Apple Watch simulator with:

```sh
flutter-watchos run -d <watch-sim>
flutter-watchos test integration_test/permission_handler_test.dart -d <watch-sim>
```
