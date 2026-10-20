## 0.0.1

First version, staged: checked on the watchOS 27.0 Simulator, not yet on a
physical watch.

* sqflite on the watch, on the system SQLite: `watchos/Package.swift` links
  `libsqlite3`, and Dart calls its C API over dart:ffi.
* sqflite's method protocol answered in Dart: open, close, execute, insert,
  update, query with paged cursors, batch with `noResult` and
  `continueOnError`, transactions with transaction ids, database files and
  bytes, as sqflite_common_ffi answers it.
* `registerWith` makes this package's factory sqflite's default on watchOS.
* Two FFI exports: `sqflite_watchos_databases_path` and
  `sqflite_watchos_sqlite_version`.
* The example's `lib/` is a small watch demo, because sqflite's own example
  depends on the unpublished `sqflite_example_common`; its official
  integration test is upstream's, unchanged.
