# sqflite_example

A watchOS-only example: laps saved to a SQLite database on the watch. Run it
on an Apple Watch simulator with:

```sh
flutter-watchos run
```

`integration_test/sqflite_test.dart` is sqflite's official integration test,
unchanged. It uses `package:test`'s `test`, which `flutter-watchos drive`
does not collect, so run it with `test`:

```sh
flutter-watchos test integration_test/sqflite_test.dart -d <watch-sim>
```
