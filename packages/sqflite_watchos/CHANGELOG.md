## 0.0.1

First version, staged: checked on the watchOS 27.0 Simulator, not yet on a
physical watch.

* sqflite on the watch, on the system SQLite: `watchos/Package.swift` links
  `libsqlite3`, and Dart calls its C API over dart:ffi.
* sqflite's method protocol answered in Dart: open, close, execute, insert,
  update, query with paged cursors, batch with `noResult` and
  `continueOnError`, transactions with transaction ids, database files and
  bytes. `lib/src/handler.dart` is adapted from sqflite_common_ffi's
  `sqflite_ffi_impl.dart` and carries its BSD-2-Clause notice.
* Arguments bind as on iOS: a `bool` as 1 or 0, a `Uint8List` or plain
  `List<int>` as a blob.
* A connection waits up to 2 seconds for another connection's lock, FMDB's
  default on iOS.
* An in-memory database is never a single instance.
* `SqfliteWatchos` extends `SqflitePlatform`; `registerWith` makes its
  `databaseFactoryWatchos` sqflite's default on watchOS.
* `sqflite_common: ">=2.5.14 <2.6.0"`: 2.5.14 fixes a hang when a cursor is
  closed inside a transaction, and the `src/` imports stop below the next
  minor.
* Two FFI exports: `sqflite_watchos_databases_path` and
  `sqflite_watchos_sqlite_version`.
* The example is sqflite 2.4.5's own. It depends on `sqflite_example_common`,
  which is not on pub.dev, so its pubspec pins that package to the
  tekartik/sqflite commit of the release. Its official integration test is
  upstream's, unchanged.
