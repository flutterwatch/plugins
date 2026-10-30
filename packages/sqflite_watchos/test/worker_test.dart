// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side tests of the background isolate that runs the handler: calls
// keep their order, errors arrive as the handler threw them, and a stop
// closes the isolate's databases. Where it matters, the same calls also run
// through a handler on the test isolate, to compare.

import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';
// ignore: implementation_imports
import 'package:sqflite_common/src/exception.dart'
    show SqfliteDatabaseException;
import 'package:sqflite_watchos/sqflite_watchos.dart';
import 'package:sqflite_watchos/src/handler.dart';
import 'package:sqflite_watchos/src/sqlite3.dart';
import 'package:sqflite_watchos/src/worker.dart';

import 'host_sqlite.dart';

/// One way to make a method call: a worker's, or a handler's.
typedef Invoke = Future<Object?> Function(String method, [Object? arguments]);

void main() {
  late Directory dir;
  late SqfliteWatchosWorker worker;
  late SqfliteWatchosHandler local;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sqflite_watchos_worker_test');
    worker = SqfliteWatchosWorker(
      libraryPath: hostSqlitePath,
      databasesPath: dir.path,
    );
    local = SqfliteWatchosHandler(
      Sqlite3Library(hostSqlite()),
      databasesPath: dir.path,
      platformVersion: 'watchOS test',
    );
  });

  tearDown(() async {
    // A stop that never ends fails here instead of hanging the run.
    await worker.stop().timeout(const Duration(seconds: 10));
    local.closeAll();
    dir.deleteSync(recursive: true);
  });

  /// Opens [path] through [invoke] and returns the database's id.
  Future<int> open(Invoke invoke, [String path = inMemoryDatabasePath]) async =>
      ((await invoke('openDatabase', <String, Object?>{'path': path}))!
          as Map<Object?, Object?>)['id']! as int;

  /// What [call] failed with.
  Future<Object> failure(Future<Object?> Function() call) async {
    try {
      await call();
    } catch (e) {
      return e;
    }
    throw StateError('the call did not fail');
  }

  test('calls made before the isolate starts run in the order made', () async {
    // The first call starts the isolate, and its first database is 1. None
    // of these waits for the one before it.
    final List<Future<Object?>> calls = <Future<Object?>>[
      worker.invoke(
          'openDatabase', <String, Object?>{'path': inMemoryDatabasePath}),
      worker.invoke(
          'execute', <String, Object?>{'id': 1, 'sql': 'CREATE TABLE t (x)'}),
      for (int i = 0; i < 20; i++)
        worker.invoke('insert', <String, Object?>{
          'id': 1,
          'sql': 'INSERT INTO t VALUES (?)',
          'arguments': <Object?>[i],
        }),
      worker.invoke(
          'query', <String, Object?>{'id': 1, 'sql': 'SELECT x FROM t'}),
    ];
    final List<Object?> results = await Future.wait(calls);
    expect(results.first, <String, Object?>{'id': 1});
    expect(results.sublist(2, 22), <int>[for (int i = 1; i <= 20; i++) i]);
    expect((results.last! as Map<Object?, Object?>)['rows'], <List<Object?>>[
      for (int i = 0; i < 20; i++) <Object?>[i],
    ]);
  });

  test('a call queued behind a transaction lets the calls after it run',
      () async {
    final int id = await open(worker.invoke);
    await worker.invoke(
        'execute', <String, Object?>{'id': id, 'sql': 'CREATE TABLE t (x)'});
    final Object? begun = await worker.invoke('execute', <String, Object?>{
      'id': id,
      'sql': 'BEGIN IMMEDIATE',
      'inTransaction': true,
      'transactionId': null,
    });
    final int txn = (begun! as Map<Object?, Object?>)['transactionId']! as int;
    // Queued in the isolate until the transaction ends. Were the isolate to
    // wait for it, the calls that end the transaction would never run.
    final Future<Object?> outside = worker.invoke('insert', <String, Object?>{
      'id': id,
      'sql': 'INSERT INTO t VALUES (?)',
      'arguments': <Object?>['outside'],
    });
    expect(
        await worker.invoke('insert', <String, Object?>{
          'id': id,
          'sql': 'INSERT INTO t VALUES (?)',
          'arguments': <Object?>['inside'],
          'transactionId': txn,
        }),
        1);
    await worker.invoke('execute', <String, Object?>{
      'id': id,
      'sql': 'COMMIT',
      'inTransaction': false,
      'transactionId': txn,
    });
    expect(await outside, 2);
    expect(
        ((await worker.invoke('query', <String, Object?>{
          'id': id,
          'sql': 'SELECT x FROM t'
        }))! as Map<Object?, Object?>)['rows'],
        <List<Object?>>[
          <Object?>['inside'],
          <Object?>['outside'],
        ]);
  });

  group('errors', () {
    test('a database error arrives with the fields the handler gave it',
        () async {
      Future<SqfliteDatabaseException> uniqueFailure(Invoke invoke) async {
        final int id = await open(invoke);
        await invoke('execute', <String, Object?>{
          'id': id,
          'sql': 'CREATE TABLE t (name TEXT UNIQUE)',
        });
        final Map<String, Object?> insert = <String, Object?>{
          'id': id,
          'sql': 'INSERT INTO t VALUES (?)',
          'arguments': <Object?>['a'],
        };
        await invoke('insert', insert);
        return (await failure(() => invoke('insert', insert)))
            as SqfliteDatabaseException;
      }

      final SqfliteDatabaseException here = await uniqueFailure(local.handle);
      final SqfliteDatabaseException there = await uniqueFailure(worker.invoke);
      expect(there.message, here.message);
      expect(there.result, here.result);
      expect(there.getResultCode(), here.getResultCode());
      expect(there.getResultCode(), 2067); // SQLITE_CONSTRAINT_UNIQUE
      expect(there.transactionClosed, isFalse);
      expect(there.isUniqueConstraintError('t.name'), isTrue);
      expect('$there', '$here');
    });

    test('transactionClosed arrives true when SQLite rolled back', () async {
      Future<SqfliteDatabaseException> rolledBack(Invoke invoke) async {
        final int id = await open(invoke);
        await invoke('execute', <String, Object?>{
          'id': id,
          'sql': 'CREATE TABLE t (x UNIQUE ON CONFLICT ROLLBACK)',
        });
        final Object? begun = await invoke('execute', <String, Object?>{
          'id': id,
          'sql': 'BEGIN',
          'inTransaction': true,
          'transactionId': null,
        });
        final Map<String, Object?> insert = <String, Object?>{
          'id': id,
          'sql': 'INSERT INTO t VALUES (1)',
          'transactionId': (begun! as Map<Object?, Object?>)['transactionId'],
        };
        await invoke('insert', insert);
        return (await failure(() => invoke('insert', insert)))
            as SqfliteDatabaseException;
      }

      final SqfliteDatabaseException here = await rolledBack(local.handle);
      final SqfliteDatabaseException there = await rolledBack(worker.invoke);
      expect(there.transactionClosed, isTrue);
      expect(there.transactionClosed, here.transactionClosed);
      expect(there.message, here.message);
      expect(there.result, here.result);
      expect(there.getResultCode(), here.getResultCode());
    });

    test('a file error and an unknown method keep their types', () async {
      final Map<String, Object?> missing = <String, Object?>{
        'path': 'missing.db',
      };
      final Object here =
          await failure(() => local.handle('readDatabaseBytes', missing));
      final Object there =
          await failure(() => worker.invoke('readDatabaseBytes', missing));
      expect(
          there,
          isA<PathNotFoundException>().having(
              (PathNotFoundException e) => e.path,
              'path',
              p.join(dir.path, 'missing.db')));
      expect(there.runtimeType, here.runtimeType);
      expect('$there', '$here');

      final Object unknownHere = await failure(() => local.handle('nope'));
      final Object unknownThere = await failure(() => worker.invoke('nope'));
      expect(unknownThere, isA<ArgumentError>());
      expect(unknownThere.runtimeType, unknownHere.runtimeType);
      expect('$unknownThere', '$unknownHere');
    });

    test('an argument that cannot be sent fails its call as a database error',
        () async {
      final ReceivePort port = ReceivePort();
      addTearDown(port.close);
      final int id = await open(worker.invoke);
      await expectLater(
        worker.invoke('query', <String, Object?>{
          'id': id,
          'sql': 'SELECT ?',
          'arguments': <Object?>[port],
        }),
        throwsA(isA<SqfliteDatabaseException>().having(
            (SqfliteDatabaseException e) => e.result,
            'details',
            containsPair('sql', 'SELECT ?'))),
      );
      // The call never left this isolate, and the next one is answered.
      expect(
          await worker.invoke(
              'query', <String, Object?>{'id': id, 'sql': 'SELECT 1 AS one'}),
          <String, Object?>{
            'columns': <String>['one'],
            'rows': <List<Object?>>[
              <Object?>[1],
            ],
          });
    });

    test('a library that cannot be opened fails every call', () async {
      final SqfliteWatchosWorker unbound = SqfliteWatchosWorker(
        libraryPath: p.join(dir.path, 'no_sqlite_here'),
        databasesPath: dir.path,
      );
      addTearDown(unbound.stop);
      await expectLater(
          unbound.invoke('getDatabasesPath'), throwsA(isA<ArgumentError>()));
      await expectLater(
          unbound.invoke(
              'openDatabase', <String, Object?>{'path': inMemoryDatabasePath}),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('stopping', () {
    test('stop closes every database, then the isolate ends', () async {
      final int id = await open(worker.invoke, 'locked.db');
      await worker.invoke(
          'execute', <String, Object?>{'id': id, 'sql': 'CREATE TABLE t (x)'});
      await worker.invoke('execute', <String, Object?>{
        'id': id,
        'sql': 'BEGIN IMMEDIATE',
        'inTransaction': true,
        'transactionId': null,
      });
      // Queued behind the open transaction, so the stop fails it.
      final Future<void> queued = expectLater(
          worker.invoke(
              'query', <String, Object?>{'id': id, 'sql': 'SELECT x FROM t'}),
          throwsA(isA<DatabaseException>()));
      // stop() completes on the isolate's exit message.
      await worker.stop();
      await queued;
      // The write lock went with the connection: one opened here writes at
      // once, where it would otherwise fail with SQLITE_BUSY.
      final int other = await open(local.handle, 'locked.db');
      expect(
          await local.handle('insert', <String, Object?>{
            'id': other,
            'sql': 'INSERT INTO t VALUES (1)',
          }),
          1);
      // Later calls fail as closed, and none of them hangs.
      await expectLater(
        worker.invoke('getDatabasesPath'),
        throwsA(isA<DatabaseException>().having(
            (DatabaseException e) => e.isDatabaseClosedError(),
            'closed',
            true)),
      );
    });

    test('resetForTesting stops the isolate of the factory', () async {
      SqfliteWatchos.libraryPathOverride = hostSqlitePath;
      SqfliteWatchos.databasesPathOverride = dir.path;
      await SqfliteWatchos.resetForTesting();
      final DatabaseFactory first = SqfliteWatchos.databaseFactoryWatchos;
      final Database db = await first.openDatabase('reset.db');
      await db.execute('CREATE TABLE t (x)');
      await db.execute('BEGIN IMMEDIATE');
      await SqfliteWatchos.resetForTesting();

      final DatabaseFactory second = SqfliteWatchos.databaseFactoryWatchos;
      expect(identical(second, first), isFalse);
      // The old isolate closed its connection, and the write lock with it.
      final Database next = await second.openDatabase('reset.db');
      expect(await next.insert('t', <String, Object?>{'x': 1}), 1);
      await next.close();
      // The old factory's database answers as closed.
      await expectLater(
        db.query('t'),
        throwsA(isA<DatabaseException>().having(
            (DatabaseException e) => e.isDatabaseClosedError(),
            'closed',
            true)),
      );
      await SqfliteWatchos.resetForTesting();
    });

    test(
        'a library that cannot be opened fails the first call, not the '
        'factory', () async {
      SqfliteWatchos.libraryPathOverride = p.join(dir.path, 'no_sqlite_here');
      SqfliteWatchos.databasesPathOverride = dir.path;
      await SqfliteWatchos.resetForTesting();
      // Building the factory binds nothing.
      final DatabaseFactory factory = SqfliteWatchos.databaseFactoryWatchos;
      await expectLater(
          factory.getDatabasesPath(), throwsA(isA<ArgumentError>()));
      await SqfliteWatchos.resetForTesting();
    });
  });
}
