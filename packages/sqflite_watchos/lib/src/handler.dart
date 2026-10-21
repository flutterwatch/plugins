// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// sqflite's method protocol, answered in Dart over SQLite's C API.
//
// sqflite_common drives every platform through one call,
// `invokeMethod(method, arguments)`: on iOS and Android it crosses a method
// channel, here it lands in [SqfliteWatchosHandler.handle]. The methods and
// the shape of their arguments and results are sqflite's own; the behaviour
// follows sqflite_common_ffi, the reference implementation of the protocol
// outside a method channel: transaction ids, operations queued behind
// another transaction, paged cursors, and batches that continue on error.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
// ignore: implementation_imports
import 'package:sqflite_common/src/exception.dart'
    show SqfliteDatabaseException;

import 'sqlite3.dart';

/// `inMemoryDatabasePath`.
const String _inMemory = ':memory:';

/// `paramTransactionIdValueForce`: run even though another transaction is
/// open, as sqflite_common does to roll back a recovered one.
const int _forceTransactionId = -1;

/// Statements sqflite reserves for itself, which go to no database.
const String _sqflitePragmaPrefix = 'PRAGMA sqflite_';

/// One open database and what is in flight on it.
class _Database {
  _Database({
    required this.id,
    required this.connection,
    required this.path,
    required this.readOnly,
    required this.singleInstance,
  });

  final int id;
  final SqliteConnection connection;
  final String path;
  final bool readOnly;
  final bool singleInstance;

  int _lastTransactionId = 0;
  int? currentTransactionId;

  /// Operations from outside the current transaction, run once it ends.
  final List<void Function()> queued = <void Function()>[];
  final List<void Function()> cancels = <void Function()>[];

  final Map<int, _Cursor> cursors = <int, _Cursor>{};
  int _lastCursorId = 0;

  Map<String, Object?> toDebugMap() => <String, Object?>{
        'path': path,
        'id': id,
        'readOnly': readOnly,
        'singleInstance': singleInstance,
      };

  void closeCursor(int cursorId) => cursors.remove(cursorId)?.statement.close();

  /// Runs queued operations until one opens a transaction again.
  void runQueued() {
    while (queued.isNotEmpty && currentTransactionId == null) {
      cancels.removeAt(0);
      queued.removeAt(0)();
    }
  }

  void close() {
    for (final void Function() cancel in cancels) {
      cancel();
    }
    queued.clear();
    cancels.clear();
    for (final int id in cursors.keys.toList()) {
      closeCursor(id);
    }
    connection.close();
  }
}

class _Cursor {
  _Cursor(this.id, this.statement, this.pageSize);

  final int id;
  final SqliteStatement statement;
  final int pageSize;
}

/// Answers sqflite's method calls for every database this isolate opened.
class SqfliteWatchosHandler {
  /// A handler over [library], keeping relative paths under
  /// [databasesPath] and reporting [platformVersion].
  SqfliteWatchosHandler(
    this.library, {
    required this.databasesPath,
    required this.platformVersion,
  });

  /// The SQLite C API.
  final Sqlite3Library library;

  /// Where relative database paths live.
  final String databasesPath;

  /// What `getPlatformVersion` answers.
  final String platformVersion;

  final Map<int, _Database> _databases = <int, _Database>{};
  final Map<String, _Database> _singleInstances = <String, _Database>{};
  int _lastId = 0;

  /// sqflite's log level, as set through `options`. Kept for parity; this
  /// handler logs nothing itself.
  int logLevel = 0;

  /// Runs one sqflite method call.
  Future<Object?> handle(String method, [Object? arguments]) async {
    final Map<Object?, Object?> args = arguments is Map<Object?, Object?>
        ? arguments
        : const <Object?, Object?>{};
    switch (method) {
      case 'openDatabase':
        return _guard(() => _open(args), sql: null, arguments: null);
      case 'closeDatabase':
        return _guard(() => _close(args), sql: null, arguments: null);
      case 'execute':
        return _onDatabase(args, (_Database db) => _execute(db, args));
      case 'insert':
        return _onDatabase(args, (_Database db) => _insert(db, args));
      case 'update':
        return _onDatabase(args, (_Database db) => _update(db, args));
      case 'query':
        return _onDatabase(args, (_Database db) => _query(db, args));
      case 'queryCursorNext':
        return _onDatabase(args, (_Database db) => _cursorNext(db, args));
      case 'batch':
        return _onDatabase(args, (_Database db) => _batch(db, args));
      case 'getDatabasesPath':
        return databasesPath;
      case 'getPlatformVersion':
        return platformVersion;
      case 'databaseExists':
        final String path = _path(args);
        return path != _inMemory && File(path).existsSync();
      case 'deleteDatabase':
        _delete(_path(args));
        return null;
      case 'readDatabaseBytes':
        return <String, Object?>{'bytes': File(_path(args)).readAsBytesSync()};
      case 'writeDatabaseBytes':
        final File file = File(_path(args));
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(args['bytes']! as Uint8List);
        return null;
      case 'options':
        final Object? level = args['logLevel'];
        if (level is int) {
          logLevel = level;
        }
        return null;
      case 'debugMode':
        if (arguments == true) {
          logLevel = 2; // sqfliteLogLevelVerbose
        }
        return null;
      default:
        throw ArgumentError('Invalid method $method');
    }
  }

  // ---- Paths and databases ------------------------------------------------

  String _resolve(String path) => path == _inMemory || p.isAbsolute(path)
      ? path
      : p.join(databasesPath, path);

  String _path(Map<Object?, Object?> args) => _resolve(args['path']! as String);

  bool _isClosedId(Object? id) =>
      id is int && id > 0 && id <= _lastId && !_databases.containsKey(id);

  _Database _databaseOrThrow(Map<Object?, Object?> args) {
    final Object? id = args['id'];
    final _Database? db = _databases[id];
    if (db != null) {
      return db;
    }
    if (_isClosedId(id)) {
      // Matches sqflite_common's isDatabaseClosedError.
      throw StateError('This database has already been closed');
    }
    throw StateError('Database $id not found');
  }

  Map<String, Object?> _open(Map<Object?, Object?> args) {
    final String path = _path(args);
    final bool readOnly = args['readOnly'] == true;
    final bool singleInstance = args['singleInstance'] == true;
    if (singleInstance) {
      final _Database? existing = _singleInstances[path];
      if (existing != null) {
        return <String, Object?>{'id': existing.id};
      }
    }
    if (!readOnly && path != _inMemory) {
      // sqflite creates the missing parent directories on every platform.
      Directory(p.dirname(path)).createSync(recursive: true);
    }
    final SqliteConnection connection;
    try {
      connection = library.open(
        path,
        readOnly
            ? SqliteCode.openReadOnly
            : SqliteCode.openReadWrite | SqliteCode.openCreate,
      );
    } on SqliteFailure catch (failure) {
      throw SqfliteDatabaseException(
        'open_failed: $failure',
        <String, Object?>{'path': path},
        resultCode: failure.extendedCode,
      );
    }
    final int id = ++_lastId;
    final _Database db = _Database(
      id: id,
      connection: connection,
      path: path,
      readOnly: readOnly,
      singleInstance: singleInstance,
    );
    _databases[id] = db;
    if (singleInstance) {
      _singleInstances[path] = db;
    }
    return <String, Object?>{'id': id};
  }

  Object? _close(Map<Object?, Object?> args) {
    if (_isClosedId(args['id'])) {
      // Already closed, as a single instance deleted while open is.
      return null;
    }
    final _Database db = _databaseOrThrow(args);
    _forget(db);
    return null;
  }

  void _forget(_Database db) {
    _databases.remove(db.id);
    if (identical(_singleInstances[db.path], db)) {
      _singleInstances.remove(db.path);
    }
    db.close();
  }

  void _delete(String path) {
    final _Database? open = _singleInstances[path];
    if (open != null) {
      _forget(open);
    }
    if (path == _inMemory) {
      return;
    }
    // With the files SQLite keeps beside it, as sqflite_darwin deletes them:
    // a write-ahead log left behind would be replayed into a new database
    // created at the same path.
    for (final String suffix in const <String>[
      '',
      '-wal',
      '-shm',
      '-journal'
    ]) {
      try {
        final File file = File('$path$suffix');
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {
        // As on every platform: deleting what cannot be deleted is not an
        // error.
      }
    }
  }

  // ---- Running SQL --------------------------------------------------------

  /// Runs [action] on the database the call names, or queues it while
  /// another transaction is open on that database.
  Future<Object?> _onDatabase(
    Map<Object?, Object?> args,
    Object? Function(_Database db) action,
  ) {
    final _Database db;
    try {
      db = _databaseOrThrow(args);
    } catch (e) {
      return Future<Object?>.error(_wrap(e, null, args));
    }
    final Object? transactionId = args['transactionId'];
    if (db.currentTransactionId == null) {
      return Future<Object?>.sync(() => _run(db, args, action));
    }
    if (transactionId == db.currentTransactionId ||
        transactionId == _forceTransactionId) {
      try {
        return Future<Object?>.value(_run(db, args, action));
      } catch (e, st) {
        return Future<Object?>.error(e, st);
      } finally {
        if (db.currentTransactionId == null) {
          scheduleMicrotask(db.runQueued);
        }
      }
    }
    final Completer<Object?> completer = Completer<Object?>();
    db.queued.add(() {
      try {
        completer.complete(_run(db, args, action));
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    db.cancels.add(() => completer.completeError(
        _wrap(StateError('Database has been closed'), db, args)));
    return completer.future;
  }

  /// Runs [action], turning a failure into sqflite's exception, and marks
  /// the transaction closed when SQLite rolled it back.
  Object? _run(
    _Database db,
    Map<Object?, Object?> args,
    Object? Function(_Database db) action,
  ) {
    try {
      return action(db);
    } catch (e) {
      final SqfliteDatabaseException wrapped = _wrap(e, db, args);
      if (db.currentTransactionId != null && db.connection.autocommit) {
        db.currentTransactionId = null;
        wrapped.transactionClosed = true;
        scheduleMicrotask(db.runQueued);
      }
      throw wrapped;
    }
  }

  Object? _guard(Object? Function() action,
      {required String? sql, required List<Object?>? arguments}) {
    try {
      return action();
    } catch (e) {
      throw _wrap(e, null, <Object?, Object?>{
        if (sql != null) 'sql': sql,
        if (arguments != null) 'arguments': arguments,
      });
    }
  }

  SqfliteDatabaseException _wrap(
      Object e, _Database? db, Map<Object?, Object?> args) {
    if (e is SqfliteDatabaseException) {
      return e;
    }
    final Object? sql = args['sql'];
    final Object? arguments = args['arguments'];
    final Map<String, Object?> details = <String, Object?>{
      if (db != null) 'database': db.toDebugMap(),
      if (sql != null) 'sql': sql,
      if (arguments != null) 'arguments': arguments,
    };
    return SqfliteDatabaseException(
      '$e',
      details.isEmpty ? null : details,
      resultCode: e is SqliteFailure ? e.extendedCode : null,
    );
  }

  static List<Object?> _arguments(Map<Object?, Object?> args) =>
      (args['arguments'] as List<Object?>?) ?? const <Object?>[];

  void _executeSql(_Database db, String sql, List<Object?> arguments) {
    if (sql.startsWith(_sqflitePragmaPrefix)) {
      return;
    }
    if (arguments.isEmpty) {
      db.connection.executeAll(sql);
    } else {
      db.connection.execute(sql, arguments);
    }
  }

  void _checkWritable(_Database db) {
    if (db.readOnly) {
      throw SqfliteDatabaseException('Database readonly', null);
    }
  }

  Object? _execute(_Database db, Map<Object?, Object?> args) {
    final bool? inTransactionChange = args['inTransaction'] as bool?;
    final bool entering = inTransactionChange == true &&
        args.containsKey('transactionId') &&
        args['transactionId'] == null;
    if (entering) {
      db.currentTransactionId = ++db._lastTransactionId;
    }
    try {
      _executeSql(db, args['sql']! as String, _arguments(args));
    } catch (_) {
      if (entering) {
        db.currentTransactionId = null;
      }
      rethrow;
    }
    if (entering) {
      return <String, Object?>{'transactionId': db.currentTransactionId};
    }
    if (inTransactionChange == false) {
      db.currentTransactionId = null;
    }
    return null;
  }

  /// The id of the inserted row, or null when nothing was inserted.
  int? _lastInsertId(_Database db) =>
      db.connection.changes == 0 ? null : db.connection.lastInsertRowId;

  Object? _insert(_Database db, Map<Object?, Object?> args) {
    _checkWritable(db);
    _executeSql(db, args['sql']! as String, _arguments(args));
    return _lastInsertId(db);
  }

  Object? _update(_Database db, Map<Object?, Object?> args) {
    _checkWritable(db);
    _executeSql(db, args['sql']! as String, _arguments(args));
    return db.connection.changes;
  }

  static Map<String, Object?> _pack(
          List<String> columns, List<List<Object?>> rows) =>
      <String, Object?>{'columns': columns, 'rows': rows};

  Object? _query(_Database db, Map<Object?, Object?> args) {
    final String sql = args['sql']! as String;
    final List<Object?> arguments = _arguments(args);
    final Object? pageSize = args['cursorPageSize'];
    if (pageSize is! int) {
      final ({List<String> columns, List<List<Object?>> rows}) result =
          db.connection.select(sql, arguments);
      return _pack(result.columns, result.rows);
    }
    final SqliteStatement statement = db.connection.prepare(sql, arguments);
    final _Cursor cursor = _Cursor(++db._lastCursorId, statement, pageSize);
    db.cursors[cursor.id] = cursor;
    return _page(db, cursor);
  }

  Map<String, Object?> _page(_Database db, _Cursor cursor) {
    try {
      final List<List<Object?>> rows = <List<Object?>>[];
      bool atEnd = false;
      while (rows.length < cursor.pageSize) {
        if (!cursor.statement.step()) {
          atEnd = true;
          break;
        }
        rows.add(cursor.statement.row());
      }
      final Map<String, Object?> page = _pack(cursor.statement.columns, rows);
      if (atEnd) {
        db.closeCursor(cursor.id);
      } else {
        page['cursorId'] = cursor.id;
      }
      return page;
    } catch (_) {
      db.closeCursor(cursor.id);
      rethrow;
    }
  }

  Object? _cursorNext(_Database db, Map<Object?, Object?> args) {
    final int cursorId = args['cursorId']! as int;
    if (args['cancel'] == true) {
      db.closeCursor(cursorId);
      return null;
    }
    final _Cursor? cursor = db.cursors[cursorId];
    if (cursor == null) {
      throw StateError('Cursor $cursorId not found');
    }
    return _page(db, cursor);
  }

  Object? _batch(_Database db, Map<Object?, Object?> args) {
    final bool noResult = args['noResult'] == true;
    final bool continueOnError = args['continueOnError'] == true;
    final List<Map<String, Object?>>? results =
        noResult ? null : <Map<String, Object?>>[];
    for (final Object? item in args['operations']! as List<Object?>) {
      final Map<Object?, Object?> operation = item! as Map<Object?, Object?>;
      final String method = operation['method']! as String;
      final String? sql = operation['sql'] as String?;
      final List<Object?> arguments = _arguments(operation);
      try {
        final Object? result = switch (method) {
          'insert' => () {
              _checkWritable(db);
              _executeSql(db, sql!, arguments);
              return _lastInsertId(db);
            }(),
          'update' => () {
              _checkWritable(db);
              _executeSql(db, sql!, arguments);
              return db.connection.changes;
            }(),
          'execute' => () {
              _executeSql(db, sql!, arguments);
              return null;
            }(),
          'query' => () {
              final ({List<String> columns, List<List<Object?>> rows}) r =
                  db.connection.select(sql!, arguments);
              return _pack(r.columns, r.rows);
            }(),
          _ => throw UnsupportedError('batch operation $method not supported'),
        };
        results?.add(<String, Object?>{'result': result});
      } catch (e) {
        final SqfliteDatabaseException wrapped = _wrap(e, db, operation);
        if (!continueOnError) {
          throw wrapped;
        }
        results?.add(<String, Object?>{
          'error': <String, Object?>{
            'code': 'sqlite_error',
            'message': wrapped.message,
            if (wrapped.getResultCode() != null)
              'resultCode': wrapped.getResultCode(),
            'data': <String, Object?>{
              'sql': sql,
              if (arguments.isNotEmpty) 'arguments': arguments,
            },
          },
        });
        if (db.currentTransactionId != null && db.connection.autocommit) {
          // SQLite rolled the transaction back: nothing after this counts.
          throw wrapped..transactionClosed = true;
        }
      }
    }
    return results;
  }
}
