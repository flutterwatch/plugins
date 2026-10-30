# sqflite_example

sqflite 2.4.5's own example app (`sqflite/example`), on watchOS: the test
pages of `sqflite_example_common`, which is not on pub.dev, so the pubspec
takes it from tekartik/sqflite at the commit of that release. Run it on an
Apple Watch simulator with:

```sh
flutter-watchos run
```

`integration_test/sqflite_test.dart` is sqflite's official integration test,
unchanged but for the formatting this repository's CI checks. It uses
`package:test`'s `test`, which `flutter-watchos drive` does not collect, so
run it with `test`:

```sh
flutter-watchos test integration_test/sqflite_test.dart -d <watch-sim>
```
