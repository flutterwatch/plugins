# sqflite_watchos

The watchOS implementation of [`sqflite`](https://pub.dev/packages/sqflite).

Databases are the **system SQLite**: watchOS ships `libsqlite3`, the
flutter-watchos CLI links it, and Dart calls its C API over dart:ffi.
sqflite's method protocol (open, execute, insert, update, query with cursors,
batch, transactions) is answered in Dart, the way `sqflite_common_ffi`
answers it on desktop, so the `Database` API behaves as it does on iOS and
Android.

> Scaffolded by [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
> from `sqflite_darwin`, then implemented and verified by hand.

## Usage

This is a federated plugin implementation. Apps that already depend on
`sqflite` and target watchOS only need to add this package alongside it:

```yaml
dependencies:
  sqflite: ^2.4.4
  sqflite_watchos: ^0.0.1
```

The plugin registers automatically via Flutter's federated registry — no
explicit imports required from app code. Use sqflite as usual:

```dart
final Database db = await openDatabase(
  'laps.db',
  version: 1,
  onCreate: (Database db, int version) =>
      db.execute('CREATE TABLE lap (id INTEGER PRIMARY KEY, at INTEGER)'),
);
await db.insert('lap', <String, Object?>{'at': DateTime.now().millisecondsSinceEpoch});
```

## Behaviour on watchOS

| sqflite | watchOS |
|---|---|
| `openDatabase` / `openReadOnlyDatabase` | supported; relative paths live in the app's Documents directory, as on iOS, and missing parent directories are created. A connection waits up to 2 seconds for another connection's lock, as on iOS |
| `execute` / `insert` / `update` / `delete` / `rawQuery` and friends | supported; integers are 64-bit, a `bool` argument is stored as 1 or 0, text is UTF-8, and a blob (a `Uint8List` or a `List<int>` argument) comes back as `Uint8List`. sqflite_common still warns once per type, in debug, about `bool` and `List<int>` arguments, as on every platform |
| `queryCursor` | supported, page by page |
| `batch` | supported, with `noResult` and `continueOnError` |
| `transaction` | supported; calls from outside an open transaction wait until it ends |
| `databaseExists` / `deleteDatabase` / `getDatabasesPath` | supported; deleting an open single-instance database closes it first, and the `-wal`, `-shm` and `-journal` files beside it go too, as on iOS |
| `readDatabaseBytes` / `writeDatabaseBytes` | supported |
| `DatabaseException` helpers | `isUniqueConstraintError`, `isNoSuchTableError`, `isSyntaxError`, `isOpenFailedError`, `isReadOnlyError`, `isDatabaseClosedError`; `getResultCode()` is SQLite's extended result code |

SQL runs on a background isolate, as `sqflite_common_ffi` runs it on
desktop, so a long query does not hold up a frame. The first call starts
the isolate, and every database shares it: the open databases, their
transactions and their cursors live there, and each call reaches it as a
message, with its arguments and results copied. Each isolate that uses
sqflite gets a background isolate of its own, which closes its databases
and ends when that isolate ends. Errors come back intact, as a
`DatabaseException` with SQLite's message and result code.

The 2-second wait for another connection's lock blocks that isolate, not
the UI, and calls to every other database wait behind it. Two connections
to one file opened from the same isolate cannot wait each other out: the
background isolate that would commit the first is the one waiting, so the
second waits the full 2 seconds and fails with `SQLITE_BUSY` (result code
5). Keep one connection per file, as sqflite's default
`singleInstance: true` does. On iOS each database has a queue of its own,
so there the second connection gets the lock once the first commits.

`SqfliteWatchos.sqliteVersion` reports the system SQLite's version.

## Not supported on watchOS

Every method of sqflite's protocol is answered; `PORTING_REPORT.md` lists
each under "Protocol coverage". What is left:

| sqflite | On watchOS | Why |
|---|---|---|
| `Sqflite.setDebugModeOn`, `Sqflite.devSetDebugModeOn`, `Sqflite.devSetOptions`, `Sqflite.devInvokeMethod` (all deprecated) | throw `MissingPluginException` | they call sqflite's method channel directly, not the database factory; `databaseFactory.setLogLevel` reaches this package |
| `androidSetLocale` | fails | Android only, as on iOS |

`Sqflite.firstIntValue`, `Sqflite.hex` and `Sqflite.setLockWarningInfo`
run in Dart and work. The sqflite-specific `PRAGMA sqflite_…` statements
are accepted and ignored.

## License

BSD-2-Clause, as upstream sqflite's. `lib/src/handler.dart` and
`lib/src/worker.dart` are adapted from sqflite_common_ffi and carry its
copyright notice. See `LICENSE` for the full text.
