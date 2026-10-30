// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side tests of the background isolate that runs the handler: it starts
// on the first call, calls keep their order, errors arrive as the handler
// threw them, a stop closes its databases, and it ends with the isolate that
// started it. Where it matters, the same calls also run through a handler on
// the test isolate, to compare.

import 'dart:async';
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

/// A recursive count that keeps SQLite busy for a few hundred milliseconds:
/// 0.4 s on an M-series Mac.
const String longCount = 'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL '
    'SELECT i + 1 FROM n WHERE i < 3000000) SELECT count(*) AS c FROM n';

/// Work on the factory in an isolate of its own, which ends without closing
/// anything: it opens `session.db`, takes its write lock and returns.
final class LockAndEnd {
  /// A session on the SQLite at [libraryPath], with databases under
  /// [databasesPath], that sends `locked` to [report] once it holds the lock.
  const LockAndEnd(this.libraryPath, this.databasesPath, [this.report]);

  /// The SQLite library the factory's isolate opens.
  final String libraryPath;

  /// Where `session.db` lives.
  final String databasesPath;

  /// Told once the lock is held.
  final SendPort? report;

  /// Runs the session.
  Future<void> run() async {
    SqfliteWatchos.libraryPathOverride = libraryPath;
    SqfliteWatchos.databasesPathOverride = databasesPath;
    final Database db =
        await SqfliteWatchos.databaseFactoryWatchos.openDatabase('session.db');
    await db.execute('CREATE TABLE IF NOT EXISTS t (x)');
    await db.execute('BEGIN IMMEDIATE');
    report?.send('locked');
  }
}

/// The entry point of a helper isolate that runs [session] and then has
/// nothing left to do.
void runAndEnd(LockAndEnd session) => unawaited(session.run());

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

  /// Inserts into `t` of [path] from this isolate, through a connection that
  /// waits for no lock: it fails at once with SQLITE_BUSY while another
  /// connection holds the write lock.
  Future<Object?> writeAtOnce(String path) async {
    final int id = await open(local.handle, path);
    try {
      await local.handle('execute',
          <String, Object?>{'id': id, 'sql': 'PRAGMA busy_timeout = 0'});
      return await local.handle('insert',
          <String, Object?>{'id': id, 'sql': 'INSERT INTO t VALUES (1)'});
    } finally {
      await local.handle('closeDatabase', <String, Object?>{'id': id});
    }
  }

  /// Waits, for 10 s at most, until [writeAtOnce] to [path] succeeds: until
  /// the connection of another isolate that holds its lock has closed.
  Future<void> expectWritableSoon(String path) async {
    final Stopwatch waited = Stopwatch()..start();
    while (true) {
      try {
        await writeAtOnce(path);
        return;
      } on DatabaseException catch (e) {
        if (e.getResultCode() != 5 || waited.elapsed.inSeconds >= 10) {
          rethrow;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  final Matcher closed = throwsA(isA<DatabaseException>().having(
      (DatabaseException e) => e.isDatabaseClosedError(), 'closed', true));

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

  group('starting', () {
    test('the isolate starts on the first call, not before', () async {
      expect(worker.isStarted, isFalse);
      await worker.invoke('getDatabasesPath');
      expect(worker.isStarted, isTrue);
    });

    test('building the factory starts no isolate', () async {
      SqfliteWatchos.libraryPathOverride = hostSqlitePath;
      SqfliteWatchos.databasesPathOverride = dir.path;
      await SqfliteWatchos.resetForTesting();
      expect(SqfliteWatchos.databaseFactoryWatchos, isNotNull);
      // A worker that never started stops within the microtask queue. A
      // started one stops on its isolate's exit message, which is an event,
      // so it could not have stopped yet.
      bool stopped = false;
      unawaited(SqfliteWatchos.resetForTesting().then((_) {
        stopped = true;
      }));
      await Future<void>.value();
      expect(stopped, isTrue);
    });
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
      // The details hold the SQL and its arguments, but no database: only
      // the isolate knows it, and the call never reached the isolate.
      await expectLater(
        worker.invoke('query', <String, Object?>{
          'id': id,
          'sql': 'SELECT ?',
          'arguments': <Object?>[port],
        }),
        throwsA(isA<SqfliteDatabaseException>().having(
            (SqfliteDatabaseException e) => e.result,
            'details',
            allOf(
                containsPair('sql', 'SELECT ?'), isNot(contains('database'))))),
      );
      // The isolate answers the next call.
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

    test('an argument that cannot be sent fails a whole batch', () async {
      final ReceivePort port = ReceivePort();
      addTearDown(port.close);
      final int id = await open(worker.invoke);
      await worker.invoke(
          'execute', <String, Object?>{'id': id, 'sql': 'CREATE TABLE t (x)'});
      Map<String, Object?> insert(Object value) => <String, Object?>{
            'method': 'insert',
            'sql': 'INSERT INTO t VALUES (?)',
            'arguments': <Object?>[value],
          };
      // As a method channel's codec fails such a call on iOS: none of its
      // operations runs, continueOnError cannot apply, and the error has no
      // details.
      await expectLater(
        worker.invoke('batch', <String, Object?>{
          'id': id,
          'continueOnError': true,
          'operations': <Object?>[insert(1), insert(port), insert(2)],
        }),
        throwsA(isA<SqfliteDatabaseException>().having(
            (SqfliteDatabaseException e) => e.result, 'details', isNull)),
      );
      expect(
          ((await worker.invoke('query', <String, Object?>{
            'id': id,
            'sql': 'SELECT x FROM t'
          }))! as Map<Object?, Object?>)['rows'],
          isEmpty);
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
      // Queued behind the open transaction, so closing the database fails it.
      Object? queuedError;
      final Future<void> queued = worker.invoke('query', <String, Object?>{
        'id': id,
        'sql': 'SELECT x FROM t'
      }).then<void>((_) {}, onError: (Object e) {
        queuedError = e;
      });
      await worker.stop();
      // stop() completes on the isolate's exit message, which comes after
      // every answer: the handler's own error for the queued call is in.
      expect(
          queuedError,
          isA<SqfliteDatabaseException>()
              .having((SqfliteDatabaseException e) => e.message, 'message',
                  'Bad state: Database has been closed')
              .having((SqfliteDatabaseException e) => e.result, 'details',
                  containsPair('sql', 'SELECT x FROM t')));
      await queued;
      // The write lock went with the connection.
      expect(await writeAtOnce('locked.db'), 1);
      // Later calls fail as closed, and none of them hangs.
      await expectLater(worker.invoke('getDatabasesPath'), closed);
    });

    test('stop lets the calls already made finish first', () async {
      final int id = await open(worker.invoke);
      await worker.invoke(
          'execute', <String, Object?>{'id': id, 'sql': 'CREATE TABLE t (x)'});
      final List<String> order = <String>[];
      // Both still running or waiting in the isolate when the stop is posted.
      final Future<Object?> count = worker.invoke('query', <String, Object?>{
        'id': id,
        'sql': longCount
      }).whenComplete(() => order.add('count'));
      final Future<Object?> insert = worker.invoke('insert', <String, Object?>{
        'id': id,
        'sql': 'INSERT INTO t VALUES (1)',
      }).whenComplete(() => order.add('insert'));
      await worker.stop().whenComplete(() => order.add('stop'));
      expect(order, <String>['count', 'insert', 'stop']);
      expect(
          (await count)! as Map<Object?, Object?>,
          containsPair('rows', <List<Object?>>[
            <Object?>[3000000],
          ]));
      expect(await insert, 1);
    });

    test('a stop made before the isolate has sent its port follows the calls',
        () async {
      // The first call starts the isolate; the stop is posted before its
      // port arrives, behind these three.
      final List<Future<Object?>> calls = <Future<Object?>>[
        worker.invoke('openDatabase', <String, Object?>{'path': 'early.db'}),
        worker.invoke(
            'execute', <String, Object?>{'id': 1, 'sql': 'CREATE TABLE t (x)'}),
        worker.invoke(
            'execute', <String, Object?>{'id': 1, 'sql': 'BEGIN IMMEDIATE'}),
      ];
      final Future<void> stopped = worker.stop();
      expect(await Future.wait(calls), <Object?>[
        <String, Object?>{'id': 1},
        null,
        null,
      ]);
      await stopped;
      // The stop reached the isolate, which closed the database and so its
      // write lock.
      expect(await writeAtOnce('early.db'), 1);
    });

    test('resetForTesting stops the isolate of the factory', () async {
      SqfliteWatchos.libraryPathOverride = hostSqlitePath;
      SqfliteWatchos.databasesPathOverride = dir.path;
      await SqfliteWatchos.resetForTesting();
      final DatabaseFactory first = SqfliteWatchos.databaseFactoryWatchos;
      final Database db = await first.openDatabase('reset.db');
      await db.execute('CREATE TABLE t (x)');
      await db.execute('BEGIN IMMEDIATE');
      // Posted to the old isolate, and still running there at the reset.
      bool counted = false;
      final Future<void> count = db.rawQuery(longCount).then((_) {
        counted = true;
      });
      await Future<void>.delayed(Duration.zero);
      await SqfliteWatchos.resetForTesting();
      // The reset completed once the old isolate had answered it and ended.
      expect(counted, isTrue);
      await count;
      final DatabaseFactory second = SqfliteWatchos.databaseFactoryWatchos;
      expect(identical(second, first), isFalse);
      // The old isolate closed its connection, and the write lock with it.
      expect(await writeAtOnce('reset.db'), 1);
      final Database next = await second.openDatabase('reset.db');
      expect(await next.query('t'), hasLength(1));
      await next.close();
      // The old factory's database answers as closed.
      await expectLater(db.query('t'), closed);
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

    test('an isolate that ends abnormally fails the calls it never answered',
        () async {
      final int id = await open(worker.invoke, 'ended.db');
      await worker.invoke(
          'execute', <String, Object?>{'id': id, 'sql': 'CREATE TABLE t (x)'});
      await worker.invoke('execute', <String, Object?>{
        'id': id,
        'sql': 'BEGIN IMMEDIATE',
        'inTransaction': true,
        'transactionId': null,
      });
      // Queued behind the open transaction: only the isolate's end fails it,
      // with the error the isolate reported before it ended.
      final Future<void> queued = expectLater(
        worker.invoke(
            'query', <String, Object?>{'id': id, 'sql': 'SELECT x FROM t'}),
        throwsA(isA<DatabaseException>()
            .having((DatabaseException e) => e.isDatabaseClosedError(),
                'closed', true)
            .having((DatabaseException e) => '$e', 'text',
                contains('crashForTesting'))),
      );
      worker.crashForTesting();
      await queued;
      await expectLater(worker.invoke('getDatabasesPath'), closed);
    });
  });

  group('lifetime', () {
    test('an Isolate.run session leaves no worker once it ends', () async {
      await Isolate.run(LockAndEnd(hostSqlitePath, dir.path).run);
      // The session ended with its database open and its write lock held.
      // Its end stopped its worker, which closed the database, and only a
      // stop does that, before it ended too.
      await expectWritableSoon('session.db');
    });

    test('a helper isolate that used the factory ends on its own', () async {
      final ReceivePort events = ReceivePort();
      addTearDown(events.close);
      await Isolate.spawn<LockAndEnd>(
        runAndEnd,
        LockAndEnd(hostSqlitePath, dir.path, events.sendPort),
        onExit: events.sendPort,
        onError: events.sendPort,
      );
      // Its session, then its exit (null): nothing keeps it alive once its
      // last call is answered.
      expect(await events.take(2).toList().timeout(const Duration(seconds: 10)),
          <Object?>['locked', null]);
      // Its end stopped its worker too.
      await expectWritableSoon('session.db');
    });
  });
}
