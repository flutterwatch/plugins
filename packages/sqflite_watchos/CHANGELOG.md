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
* SQL runs on a background isolate, as sqflite_common_ffi's
  `databaseFactoryFfi` runs it, so a long query does not hold up a frame
  (#20). One isolate, started by the first call and shared by every
  database, holds the open databases, their transactions and cursors. Each
  isolate that uses sqflite gets its own, which closes its databases and
  ends when that isolate ends, and keeps that isolate alive only while an
  answer is due, so the isolate can still end on its own. A
  `SqfliteDatabaseException` crosses back as its message, details, result
  code and `transactionClosed`, so sqflite_common sees the same error; a
  file error or an `ArgumentError` keeps its type. `lib/src/worker.dart` is
  adapted from sqflite_common_ffi's `isolate_io.dart` and `method_call.dart`
  and carries its BSD-2-Clause notice.
* A value that cannot be sent to the background isolate, such as a port or
  the `Future` of a forgotten `await`, fails the whole call before it is
  sent, as a method channel's codec fails it on iOS: a batch runs none of
  its operations, and `continueOnError` cannot apply. The error's details
  hold the call's SQL and arguments but not its database; a batch's error
  has no details.
* Arguments bind as on iOS: a `bool` as 1 or 0, a `Uint8List` or plain
  `List<int>` as a blob.
* A connection waits up to 2 seconds for another connection's lock, FMDB's
  default on iOS. The wait blocks the background isolate, not the UI. Two
  connections to one file opened from the same isolate share its background
  isolate, so they cannot wait each other out.
* An in-memory database is never a single instance.
* `SqfliteWatchos` extends `SqflitePlatform`; `registerWith` makes its
  `databaseFactoryWatchos` sqflite's default on watchOS, and binds nothing
  until the first call.
* Test hooks: `SqfliteWatchos.libraryPathOverride`, the path of a SQLite
  library for the background isolate to open, and `databasesPathOverride`.
  `resetForTesting` closes the isolate's databases and stops it.
* `sqflite_common: ">=2.5.14 <2.6.0"`: 2.5.14 fixes a hang when a cursor is
  closed inside a transaction, and the `src/` imports stop below the next
  minor.
* Two FFI exports: `sqflite_watchos_databases_path` and
  `sqflite_watchos_sqlite_version`.
* The example is sqflite 2.4.5's own. It depends on `sqflite_example_common`,
  which is not on pub.dev, so its pubspec pins that package to the
  tekartik/sqflite commit of the release. Its official integration test is
  upstream's, unchanged.
