// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side tests that run real SQL. The handler binds SQLite's C API, which
// macOS ships too, so these point it at the system libsqlite3 and drive it
// through sqflite_common's own Database API, the way an app does. The watch
// resolves the same functions from its process instead.

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';
// ignore: implementation_imports
import 'package:sqflite_common/src/exception.dart'
    show SqfliteDatabaseException;
import 'package:sqflite_watchos/sqflite_watchos.dart';
import 'package:sqflite_watchos/src/handler.dart';
import 'package:sqflite_watchos/src/sqlite3.dart';

void main() {
  late Directory dir;
  late DatabaseFactory factory;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('sqflite_watchos_test');
    SqfliteWatchos.libraryOverride =
        DynamicLibrary.open('/usr/lib/libsqlite3.dylib');
    SqfliteWatchos.databasesPathOverride = dir.path;
    SqfliteWatchos.resetForTesting();
    factory = SqfliteWatchos.databaseFactory;
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  Future<Database> openFresh(String name,
      {OpenDatabaseOptions? options}) async {
    await factory.deleteDatabase(name);
    return factory.openDatabase(name, options: options);
  }

  test('registerWith makes the watchOS factory the default', () {
    databaseFactoryOrNull = null;
    SqfliteWatchos.registerWith();
    expect(identical(databaseFactoryOrNull, factory), isTrue);
  });

  test('registerWith keeps a factory the app already set', () {
    final DatabaseFactory other = factory;
    databaseFactoryOrNull = other;
    SqfliteWatchos.registerWith();
    expect(identical(databaseFactoryOrNull, other), isTrue);
  });

  test('getDatabasesPath is where relative paths go', () async {
    expect(await factory.getDatabasesPath(), dir.path);
    final Database db = await openFresh('relative.db');
    expect(db.path, p.join(dir.path, 'relative.db'));
    await db.close();
    expect(File(p.join(dir.path, 'relative.db')).existsSync(), isTrue);
  });

  test('a missing parent directory is created', () async {
    final Database db = await openFresh(p.join('sub', 'dir', 'nested.db'));
    await db.close();
    expect(
        File(p.join(dir.path, 'sub', 'dir', 'nested.db')).existsSync(), isTrue);
  });

  test('every SQLite type comes back as it went in', () async {
    final Database db = await openFresh('types.db');
    await db.execute('CREATE TABLE t (i INTEGER, r REAL, s TEXT, b BLOB, n)');
    final Uint8List blob = Uint8List.fromList(<int>[0, 1, 2, 254, 255]);
    await db.insert('t', <String, Object?>{
      'i': 4611686018427387904, // 2^62: beyond a double's exact integers
      'r': 3.25,
      's': 'İstanbul ☕ 日本',
      'b': blob,
      'n': null,
    });
    await db.insert('t', <String, Object?>{
      'i': -1,
      'r': -0.5,
      's': '',
      'b': Uint8List(0),
      'n': null,
    });
    final List<Map<String, Object?>> rows = await db.query('t');
    expect(rows[0]['i'], 4611686018427387904);
    expect(rows[0]['r'], 3.25);
    expect(rows[0]['s'], 'İstanbul ☕ 日本');
    expect(rows[0]['b'], blob);
    expect(rows[0]['n'], isNull);
    expect(rows[1]['s'], '');
    expect(rows[1]['b'], Uint8List(0));
    await db.close();
  });

  test('insert returns the row id, and 0 when nothing was inserted', () async {
    final Database db = await openFresh('insert.db');
    await db
        .execute('CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT UNIQUE)');
    expect(await db.insert('t', <String, Object?>{'name': 'a'}), 1);
    expect(await db.insert('t', <String, Object?>{'name': 'b'}), 2);
    expect(
        await db.insert('t', <String, Object?>{'name': 'a'},
            conflictAlgorithm: ConflictAlgorithm.ignore),
        0);
    await db.close();
  });

  test('update and delete return the changed row count', () async {
    final Database db = await openFresh('update.db');
    await db.execute('CREATE TABLE t (x INTEGER)');
    for (int i = 0; i < 5; i++) {
      await db.insert('t', <String, Object?>{'x': i});
    }
    expect(await db.update('t', <String, Object?>{'x': 10}, where: 'x > 2'), 2);
    expect(await db.delete('t', where: 'x = 10'), 2);
    expect(await db.rawUpdate('UPDATE t SET x = x + 1'), 3);
    await db.close();
  });

  test('several statements run in one execute', () async {
    final Database db = await openFresh('multi.db');
    await db.execute('CREATE TABLE a (x); CREATE TABLE b (y); '
        'INSERT INTO a VALUES (1); INSERT INTO b VALUES (2);');
    expect(await db.rawQuery('SELECT x FROM a'), <Map<String, Object?>>[
      <String, Object?>{'x': 1},
    ]);
    expect(await db.rawQuery('SELECT y FROM b'), <Map<String, Object?>>[
      <String, Object?>{'y': 2},
    ]);
    await db.close();
  });

  test(
      'numbered parameters and duplicated columns read as on other '
      'platforms', () async {
    final Database db = await factory.openDatabase(inMemoryDatabasePath);
    expect(
        await db.rawQuery('SELECT ?1 + ?2', <Object?>[3, 4]),
        <Map<String, Object?>>[
          <String, Object?>{'?1 + ?2': 7},
        ]);
    await db.execute('CREATE TABLE t (col1 INTEGER, col2 INTEGER)');
    await db.insert('t', <String, Object?>{'col1': 1, 'col2': 2});
    expect(
        await db
            .rawQuery('SELECT t.col1, col1, t.col2, col2 AS col1 FROM t AS t'),
        <Map<String, Object?>>[
          <String, Object?>{'col1': 2, 'col2': 2},
        ]);
    await db.close();
  });

  test('versions run onCreate and onUpgrade', () async {
    final List<String> calls = <String>[];
    Database db = await openFresh(
      'version.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database db, int version) async {
          calls.add('create $version');
          await db.execute('CREATE TABLE t (x)');
        },
      ),
    );
    expect(await db.getVersion(), 1);
    await db.close();
    db = await factory.openDatabase(
      'version.db',
      options: OpenDatabaseOptions(
        version: 2,
        onUpgrade: (Database db, int from, int to) async {
          calls.add('upgrade $from $to');
        },
      ),
    );
    expect(await db.getVersion(), 2);
    expect(calls, <String>['create 1', 'upgrade 1 2']);
    await db.close();
  });

  group('errors', () {
    test('a unique constraint names itself and carries its code', () async {
      final Database db = await openFresh('unique.db');
      await db.execute('CREATE TABLE t (name TEXT UNIQUE)');
      await db.insert('t', <String, Object?>{'name': 'a'});
      try {
        await db.insert('t', <String, Object?>{'name': 'a'});
        fail('the second insert should fail');
      } on DatabaseException catch (e) {
        expect(e.isUniqueConstraintError('t.name'), isTrue);
        expect(e.getResultCode(), 2067); // SQLITE_CONSTRAINT_UNIQUE
      }
      await db.close();
    });

    test('a syntax error and a missing table are recognised', () async {
      final Database db = await factory.openDatabase(inMemoryDatabasePath);
      await expectLater(
        db.execute('CREAT TABLE t (x)'),
        throwsA(isA<DatabaseException>().having(
            (DatabaseException e) => e.isSyntaxError(), 'syntax', true)),
      );
      await expectLater(
        db.query('missing'),
        throwsA(isA<DatabaseException>().having(
            (DatabaseException e) => e.isNoSuchTableError('missing'),
            'no such table',
            true)),
      );
      await db.close();
    });

    test('opening a missing database read-only fails to open', () async {
      await factory.deleteDatabase('absent.db');
      await expectLater(
        factory.openDatabase('absent.db',
            options: OpenDatabaseOptions(readOnly: true)),
        throwsA(isA<DatabaseException>().having(
            (DatabaseException e) => e.isOpenFailedError(),
            'open failed',
            true)),
      );
    });

    test('writing to a read-only database fails as read-only', () async {
      final Database rw = await openFresh('readonly.db');
      await rw.execute('CREATE TABLE t (x)');
      await rw.close();
      final Database ro = await factory.openDatabase('readonly.db',
          options: OpenDatabaseOptions(readOnly: true));
      await expectLater(
        ro.insert('t', <String, Object?>{'x': 1}),
        throwsA(isA<DatabaseException>().having(
            (DatabaseException e) => e.isReadOnlyError(), 'readonly', true)),
      );
      expect(await ro.query('t'), isEmpty);
      await ro.close();
    });

    test('a file that is not a database opens, then fails to read', () async {
      final File file = File(p.join(dir.path, 'not_a_database.db'))
        ..writeAsStringSync('test');
      final Database db = await factory.openDatabase(file.path,
          options: OpenDatabaseOptions(readOnly: true));
      await expectLater(db.getVersion(), throwsA(isA<DatabaseException>()));
      await db.close();
      expect(file.readAsStringSync(), 'test');
    });

    test('a closed database says so', () async {
      final Database db = await openFresh('closed.db');
      await db.close();
      // sqflite_common refuses before the call reaches the handler, and
      // synchronously.
      await expectLater(
        () => db.query('sqlite_master'),
        throwsA(isA<DatabaseException>().having(
            (DatabaseException e) => e.isDatabaseClosedError(),
            'closed',
            true)),
      );
    });
  });

  group('transactions', () {
    test('a transaction commits', () async {
      final Database db = await openFresh('commit.db');
      await db.execute('CREATE TABLE t (x)');
      await db.transaction((Transaction txn) async {
        await txn.insert('t', <String, Object?>{'x': 1});
        await txn.insert('t', <String, Object?>{'x': 2});
      });
      expect(await db.query('t'), hasLength(2));
      await db.close();
    });

    test('a failing transaction rolls back', () async {
      final Database db = await openFresh('rollback.db');
      await db.execute('CREATE TABLE t (x UNIQUE)');
      await expectLater(
        db.transaction((Transaction txn) async {
          await txn.insert('t', <String, Object?>{'x': 1});
          await txn.insert('t', <String, Object?>{'x': 1});
        }),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('t'), isEmpty);
      await db.close();
    });

    test('a call outside a running transaction waits for it', () async {
      final Database db = await openFresh('queue.db');
      await db.execute('CREATE TABLE t (x)');
      final Completer<void> inside = Completer<void>();
      final Completer<void> release = Completer<void>();
      final Future<void> txn = db.transaction((Transaction txn) async {
        await txn.insert('t', <String, Object?>{'x': 1});
        inside.complete();
        await release.future;
        await txn.insert('t', <String, Object?>{'x': 2});
      });
      await inside.future;
      final Future<List<Map<String, Object?>>> outside = db.query('t');
      bool outsideDone = false;
      unawaited(outside.then((_) => outsideDone = true));
      await pumpEventQueue();
      expect(outsideDone, isFalse, reason: 'the transaction is still open');
      release.complete();
      await txn;
      expect(await outside, hasLength(2),
          reason: 'it ran after the transaction committed');
      await db.close();
    });

    test('closing inside a raw transaction, then reopening, works', () async {
      Database db = await openFresh('close_in_txn.db',
          options: OpenDatabaseOptions(version: 1));
      await db.execute('BEGIN TRANSACTION');
      await db.close();
      db = await factory.openDatabase('close_in_txn.db',
          options: OpenDatabaseOptions(version: 1));
      expect(await db.getVersion(), 1);
      await db.close();
    });
  });

  group('batch', () {
    test('results come back in order', () async {
      final Database db = await openFresh('batch.db');
      final Batch batch = db.batch()
        ..execute('CREATE TABLE t (id INTEGER PRIMARY KEY, x)')
        ..insert('t', <String, Object?>{'x': 'a'})
        ..insert('t', <String, Object?>{'x': 'b'})
        ..update('t', <String, Object?>{'x': 'c'}, where: 'id = 1')
        ..query('t', columns: <String>['x']);
      final List<Object?> results = await batch.commit();
      expect(results[1], 1);
      expect(results[2], 2);
      expect(results[3], 1);
      expect(results[4], <Map<String, Object?>>[
        <String, Object?>{'x': 'c'},
        <String, Object?>{'x': 'b'},
      ]);
      await db.close();
    });

    test('continueOnError keeps going and reports the failure', () async {
      final Database db = await openFresh('batch_errors.db');
      await db.execute('CREATE TABLE t (x UNIQUE)');
      final Batch batch = db.batch()
        ..insert('t', <String, Object?>{'x': 1})
        ..insert('t', <String, Object?>{'x': 1})
        ..insert('t', <String, Object?>{'x': 2});
      final List<Object?> results = await batch.commit(continueOnError: true);
      expect(results[0], 1);
      expect(results[1], isA<DatabaseException>());
      expect(
          (results[1]! as DatabaseException).isUniqueConstraintError(), isTrue);
      // The failed insert used no row id.
      expect(results[2], 2);
      expect(await db.query('t'), hasLength(2));
      await db.close();
    });

    test('noResult returns nothing and still runs', () async {
      final Database db = await openFresh('batch_noresult.db');
      final Batch batch = db.batch()
        ..execute('CREATE TABLE t (x)')
        ..insert('t', <String, Object?>{'x': 1});
      expect(await batch.commit(noResult: true), isEmpty);
      expect(await db.query('t'), hasLength(1));
      await db.close();
    });
  });

  group('cursors', () {
    late Database db;

    setUp(() async {
      db = await factory.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE t (x INTEGER)');
      final Batch batch = db.batch();
      for (int i = 0; i < 7; i++) {
        batch.insert('t', <String, Object?>{'x': i});
      }
      await batch.commit(noResult: true);
    });

    tearDown(() => db.close());

    test('a cursor pages through every row', () async {
      final QueryCursor cursor =
          await db.queryCursor('t', orderBy: 'x', bufferSize: 3);
      final List<Object?> seen = <Object?>[];
      while (await cursor.moveNext()) {
        seen.add(cursor.current['x']);
      }
      expect(seen, <int>[0, 1, 2, 3, 4, 5, 6]);
    });

    test('a cursor closed early releases its statement', () async {
      final QueryCursor cursor =
          await db.queryCursor('t', orderBy: 'x', bufferSize: 2);
      expect(await cursor.moveNext(), isTrue);
      await cursor.close();
      // A statement left open would keep the table busy for this drop.
      await db.execute('DROP TABLE t');
    });
  });

  group('files', () {
    test('databaseExists and deleteDatabase', () async {
      expect(await factory.databaseExists(inMemoryDatabasePath), isFalse);
      await factory.deleteDatabase('exists.db');
      expect(await factory.databaseExists('exists.db'), isFalse);
      final Database db = await factory.openDatabase('exists.db');
      expect(await factory.databaseExists('exists.db'), isTrue);
      await db.close();
      await factory.deleteDatabase('exists.db');
      expect(await factory.databaseExists('exists.db'), isFalse);
    });

    test('deleteDatabase deletes the files SQLite keeps beside it', () async {
      final String path = p.join(dir.path, 'sidecars.db');
      final List<File> files = <File>[
        for (final String suffix in <String>['', '-wal', '-shm', '-journal'])
          File('$path$suffix')..writeAsStringSync('x'),
      ];
      await factory.deleteDatabase('sidecars.db');
      for (final File file in files) {
        expect(file.existsSync(), isFalse, reason: file.path);
      }
    });

    test('deleting an open single-instance database closes it first', () async {
      Database db = await openFresh('delete_open.db');
      await db.setVersion(1);
      await db.execute('BEGIN TRANSACTION');
      await db.setVersion(2);
      await factory.deleteDatabase('delete_open.db');
      db = await factory.openDatabase('delete_open.db');
      expect(await db.getVersion(), 0);
      await db.close();
    });

    test('database bytes can be read and written', () async {
      final Database db = await openFresh('bytes.db');
      await db.execute('CREATE TABLE t (x)');
      await db.insert('t', <String, Object?>{'x': 42});
      await db.close();
      final Uint8List bytes = await factory.readDatabaseBytes('bytes.db');
      expect(bytes.length, greaterThan(0));
      await factory.writeDatabaseBytes('copy.db', bytes);
      final Database copy = await factory.openDatabase('copy.db');
      expect(await copy.query('t'), <Map<String, Object?>>[
        <String, Object?>{'x': 42},
      ]);
      await copy.close();
    });
  });

  test('sqliteVersion reads the library version', () {
    expect(SqfliteWatchos.sqliteVersion, matches(RegExp(r'^3\.\d+\.\d+')));
  });

  group('the method protocol, below sqflite_common', () {
    late SqfliteWatchosHandler handler;

    setUp(() {
      handler = SqfliteWatchosHandler(
        Sqlite3Library(DynamicLibrary.open('/usr/lib/libsqlite3.dylib')),
        databasesPath: dir.path,
        platformVersion: 'watchOS test',
      );
    });

    Future<int> open() async =>
        ((await handler.handle('openDatabase', <String, Object?>{
          'path': inMemoryDatabasePath,
        }))! as Map<Object?, Object?>)['id']! as int;

    test('a call from outside an open transaction is queued until it ends',
        () async {
      final int id = await open();
      await handler.handle('execute', <String, Object?>{
        'id': id,
        'sql': 'CREATE TABLE t (x)',
      });
      final Object? begun = await handler.handle('execute', <String, Object?>{
        'id': id,
        'sql': 'BEGIN IMMEDIATE',
        'inTransaction': true,
        'transactionId': null,
      });
      final int txn =
          (begun! as Map<Object?, Object?>)['transactionId']! as int;

      bool outsideDone = false;
      final Future<Object?> outside =
          handler.handle('insert', <String, Object?>{
        'id': id,
        'sql': 'INSERT INTO t VALUES (?)',
        'arguments': <Object?>['outside'],
      }).then((Object? v) {
        outsideDone = true;
        return v;
      });
      await handler.handle('insert', <String, Object?>{
        'id': id,
        'sql': 'INSERT INTO t VALUES (?)',
        'arguments': <Object?>['inside'],
        'transactionId': txn,
      });
      await pumpEventQueue();
      expect(outsideDone, isFalse);

      await handler.handle('execute', <String, Object?>{
        'id': id,
        'sql': 'COMMIT',
        'inTransaction': false,
        'transactionId': txn,
      });
      expect(await outside, 2);
      final Object? rows = await handler.handle('query', <String, Object?>{
        'id': id,
        'sql': 'SELECT x FROM t',
      });
      expect((rows! as Map<Object?, Object?>)['rows'], <Object?>[
        <Object?>['inside'],
        <Object?>['outside'],
      ]);
    });

    test('closing a database cancels what is queued on it', () async {
      final int id = await open();
      final Object? begun = await handler.handle('execute', <String, Object?>{
        'id': id,
        'sql': 'BEGIN',
        'inTransaction': true,
        'transactionId': null,
      });
      expect(begun, isA<Map<Object?, Object?>>());
      final Future<Object?> queued = handler
          .handle('query', <String, Object?>{'id': id, 'sql': 'SELECT 1'});
      // Listened to before the close fails it.
      final Future<void> failed =
          expectLater(queued, throwsA(isA<DatabaseException>()));
      await handler.handle('closeDatabase', <String, Object?>{'id': id});
      await failed;
    });

    test('a closed database id answers as closed', () async {
      final int id = await open();
      await handler.handle('closeDatabase', <String, Object?>{'id': id});
      // Closing twice is fine.
      await handler.handle('closeDatabase', <String, Object?>{'id': id});
      await expectLater(
        handler.handle('query', <String, Object?>{'id': id, 'sql': 'SELECT 1'}),
        throwsA(isA<DatabaseException>().having(
            (DatabaseException e) => e.isDatabaseClosedError(),
            'closed',
            true)),
      );
    });

    test('a failure that rolls the transaction back marks it closed', () async {
      final int id = await open();
      await handler.handle('execute', <String, Object?>{
        'id': id,
        'sql': 'CREATE TABLE t (x UNIQUE ON CONFLICT ROLLBACK)',
      });
      final Object? begun = await handler.handle('execute', <String, Object?>{
        'id': id,
        'sql': 'BEGIN',
        'inTransaction': true,
        'transactionId': null,
      });
      final int txn =
          (begun! as Map<Object?, Object?>)['transactionId']! as int;
      Future<Object?> insert() => handler.handle('insert', <String, Object?>{
            'id': id,
            'sql': 'INSERT INTO t VALUES (1)',
            'transactionId': txn,
          });
      await insert();
      await expectLater(
        insert(),
        throwsA(isA<SqfliteDatabaseException>().having(
            (SqfliteDatabaseException e) => e.transactionClosed,
            'transactionClosed',
            true)),
      );
      // The database takes calls from outside again at once.
      expect(
          await handler
              .handle('query', <String, Object?>{'id': id, 'sql': 'SELECT 1'}),
          isNotNull);
    });

    test('getPlatformVersion and an unknown method', () async {
      expect(await handler.handle('getPlatformVersion'), 'watchOS test');
      await expectLater(handler.handle('nope'), throwsA(isA<ArgumentError>()));
    });
  });
}
