// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The part of SQLite's C API this package uses, bound over dart:ffi.
//
// On the watch these resolve from the process: watchOS ships libsqlite3 and
// the CLI links it. Host tests pass the macOS system library instead, so the
// same code runs real SQL there.

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// An open `sqlite3*` connection.
final class Sqlite3 extends Opaque {}

/// A prepared `sqlite3_stmt*`.
final class Sqlite3Statement extends Opaque {}

/// Result codes and flags from `sqlite3.h`.
abstract final class SqliteCode {
  /// `SQLITE_OK`.
  static const int ok = 0;

  /// `SQLITE_ROW`.
  static const int row = 100;

  /// `SQLITE_DONE`.
  static const int done = 101;

  /// `SQLITE_OPEN_READONLY`.
  static const int openReadOnly = 0x00000001;

  /// `SQLITE_OPEN_READWRITE`.
  static const int openReadWrite = 0x00000002;

  /// `SQLITE_OPEN_CREATE`.
  static const int openCreate = 0x00000004;

  /// `SQLITE_OPEN_FULLMUTEX`.
  static const int openFullMutex = 0x00010000;

  /// `SQLITE_INTEGER`.
  static const int typeInteger = 1;

  /// `SQLITE_FLOAT`.
  static const int typeFloat = 2;

  /// `SQLITE_TEXT`.
  static const int typeText = 3;

  /// `SQLITE_BLOB`.
  static const int typeBlob = 4;
}

typedef _Destructor = Pointer<NativeFunction<Void Function(Pointer<Void>)>>;

/// `SQLITE_TRANSIENT`: SQLite copies a bound value before the call returns,
/// so the Dart-side buffer can go right after.
final _Destructor _transient = _Destructor.fromAddress(-1);

/// A failed SQLite call: its extended result code and `sqlite3_errmsg`.
class SqliteFailure implements Exception {
  /// A failure with these values.
  const SqliteFailure(this.extendedCode, this.message);

  /// The extended result code, for example 2067 for a UNIQUE constraint.
  final int extendedCode;

  /// The message SQLite gave.
  final String message;

  @override
  String toString() => '$message (code $extendedCode)';
}

/// The SQLite C functions, resolved from one library.
class Sqlite3Library {
  /// Binds the functions in [library].
  Sqlite3Library(DynamicLibrary library)
      : _openV2 = library.lookupFunction<
            Int32 Function(
                Pointer<Utf8>, Pointer<Pointer<Sqlite3>>, Int32, Pointer<Utf8>),
            int Function(Pointer<Utf8>, Pointer<Pointer<Sqlite3>>, int,
                Pointer<Utf8>)>('sqlite3_open_v2'),
        _closeV2 = library.lookupFunction<Int32 Function(Pointer<Sqlite3>),
            int Function(Pointer<Sqlite3>)>('sqlite3_close_v2'),
        _extendedResultCodes = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3>, Int32),
            int Function(
                Pointer<Sqlite3>, int)>('sqlite3_extended_result_codes'),
        _prepareV2 = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3>, Pointer<Uint8>, Int32,
                Pointer<Pointer<Sqlite3Statement>>, Pointer<Pointer<Uint8>>),
            int Function(
                Pointer<Sqlite3>,
                Pointer<Uint8>,
                int,
                Pointer<Pointer<Sqlite3Statement>>,
                Pointer<Pointer<Uint8>>)>('sqlite3_prepare_v2'),
        _step = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3Statement>),
            int Function(Pointer<Sqlite3Statement>)>('sqlite3_step'),
        _finalize = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3Statement>),
            int Function(Pointer<Sqlite3Statement>)>('sqlite3_finalize'),
        _bindParameterCount = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3Statement>),
            int Function(
                Pointer<Sqlite3Statement>)>('sqlite3_bind_parameter_count'),
        _bindNull = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3Statement>, Int32),
            int Function(Pointer<Sqlite3Statement>, int)>('sqlite3_bind_null'),
        _bindInt64 = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3Statement>, Int32, Int64),
            int Function(
                Pointer<Sqlite3Statement>, int, int)>('sqlite3_bind_int64'),
        _bindDouble = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3Statement>, Int32, Double),
            int Function(
                Pointer<Sqlite3Statement>, int, double)>('sqlite3_bind_double'),
        _bindText = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3Statement>, Int32, Pointer<Uint8>,
                Int32, _Destructor),
            int Function(Pointer<Sqlite3Statement>, int, Pointer<Uint8>, int,
                _Destructor)>('sqlite3_bind_text'),
        _bindBlob = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3Statement>, Int32, Pointer<Uint8>,
                Int32, _Destructor),
            int Function(Pointer<Sqlite3Statement>, int, Pointer<Uint8>, int,
                _Destructor)>('sqlite3_bind_blob'),
        _bindZeroBlob = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3Statement>, Int32, Int32),
            int Function(
                Pointer<Sqlite3Statement>, int, int)>('sqlite3_bind_zeroblob'),
        _columnCount = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3Statement>),
            int Function(Pointer<Sqlite3Statement>)>('sqlite3_column_count'),
        _columnName = library.lookupFunction<
            Pointer<Utf8> Function(Pointer<Sqlite3Statement>, Int32),
            Pointer<Utf8> Function(
                Pointer<Sqlite3Statement>, int)>('sqlite3_column_name'),
        _columnType = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3Statement>, Int32),
            int Function(
                Pointer<Sqlite3Statement>, int)>('sqlite3_column_type'),
        _columnInt64 = library.lookupFunction<
            Int64 Function(Pointer<Sqlite3Statement>, Int32),
            int Function(
                Pointer<Sqlite3Statement>, int)>('sqlite3_column_int64'),
        _columnDouble = library.lookupFunction<
            Double Function(Pointer<Sqlite3Statement>, Int32),
            double Function(
                Pointer<Sqlite3Statement>, int)>('sqlite3_column_double'),
        _columnText = library.lookupFunction<
            Pointer<Uint8> Function(Pointer<Sqlite3Statement>, Int32),
            Pointer<Uint8> Function(
                Pointer<Sqlite3Statement>, int)>('sqlite3_column_text'),
        _columnBlob = library.lookupFunction<
            Pointer<Uint8> Function(Pointer<Sqlite3Statement>, Int32),
            Pointer<Uint8> Function(
                Pointer<Sqlite3Statement>, int)>('sqlite3_column_blob'),
        _columnBytes = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3Statement>, Int32),
            int Function(
                Pointer<Sqlite3Statement>, int)>('sqlite3_column_bytes'),
        _errmsg = library.lookupFunction<
            Pointer<Utf8> Function(Pointer<Sqlite3>),
            Pointer<Utf8> Function(Pointer<Sqlite3>)>('sqlite3_errmsg'),
        _errstr = library.lookupFunction<Pointer<Utf8> Function(Int32),
            Pointer<Utf8> Function(int)>('sqlite3_errstr'),
        _extendedErrcode = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3>),
            int Function(Pointer<Sqlite3>)>('sqlite3_extended_errcode'),
        _changes = library.lookupFunction<Int32 Function(Pointer<Sqlite3>),
            int Function(Pointer<Sqlite3>)>('sqlite3_changes'),
        _lastInsertRowId = library.lookupFunction<
            Int64 Function(Pointer<Sqlite3>),
            int Function(Pointer<Sqlite3>)>('sqlite3_last_insert_rowid'),
        _getAutocommit = library.lookupFunction<
            Int32 Function(Pointer<Sqlite3>),
            int Function(Pointer<Sqlite3>)>('sqlite3_get_autocommit'),
        _libVersion = library.lookupFunction<Pointer<Utf8> Function(),
            Pointer<Utf8> Function()>('sqlite3_libversion');

  final int Function(
      Pointer<Utf8>, Pointer<Pointer<Sqlite3>>, int, Pointer<Utf8>) _openV2;
  final int Function(Pointer<Sqlite3>) _closeV2;
  final int Function(Pointer<Sqlite3>, int) _extendedResultCodes;
  final int Function(Pointer<Sqlite3>, Pointer<Uint8>, int,
      Pointer<Pointer<Sqlite3Statement>>, Pointer<Pointer<Uint8>>) _prepareV2;
  final int Function(Pointer<Sqlite3Statement>) _step;
  final int Function(Pointer<Sqlite3Statement>) _finalize;
  final int Function(Pointer<Sqlite3Statement>) _bindParameterCount;
  final int Function(Pointer<Sqlite3Statement>, int) _bindNull;
  final int Function(Pointer<Sqlite3Statement>, int, int) _bindInt64;
  final int Function(Pointer<Sqlite3Statement>, int, double) _bindDouble;
  final int Function(
          Pointer<Sqlite3Statement>, int, Pointer<Uint8>, int, _Destructor)
      _bindText;
  final int Function(
          Pointer<Sqlite3Statement>, int, Pointer<Uint8>, int, _Destructor)
      _bindBlob;
  final int Function(Pointer<Sqlite3Statement>, int, int) _bindZeroBlob;
  final int Function(Pointer<Sqlite3Statement>) _columnCount;
  final Pointer<Utf8> Function(Pointer<Sqlite3Statement>, int) _columnName;
  final int Function(Pointer<Sqlite3Statement>, int) _columnType;
  final int Function(Pointer<Sqlite3Statement>, int) _columnInt64;
  final double Function(Pointer<Sqlite3Statement>, int) _columnDouble;
  final Pointer<Uint8> Function(Pointer<Sqlite3Statement>, int) _columnText;
  final Pointer<Uint8> Function(Pointer<Sqlite3Statement>, int) _columnBlob;
  final int Function(Pointer<Sqlite3Statement>, int) _columnBytes;
  final Pointer<Utf8> Function(Pointer<Sqlite3>) _errmsg;
  final Pointer<Utf8> Function(int) _errstr;
  final int Function(Pointer<Sqlite3>) _extendedErrcode;
  final int Function(Pointer<Sqlite3>) _changes;
  final int Function(Pointer<Sqlite3>) _lastInsertRowId;
  final int Function(Pointer<Sqlite3>) _getAutocommit;
  final Pointer<Utf8> Function() _libVersion;

  /// `sqlite3_libversion()`.
  String get version => _libVersion().toDartString();

  /// Opens [path] with [flags]. Throws a [SqliteFailure] when SQLite cannot.
  SqliteConnection open(String path, int flags) => using((Arena arena) {
        final Pointer<Pointer<Sqlite3>> out = arena<Pointer<Sqlite3>>();
        final int rc =
            _openV2(path.toNativeUtf8(allocator: arena), out, flags, nullptr);
        final Pointer<Sqlite3> db = out.value;
        if (rc != SqliteCode.ok) {
          final SqliteFailure failure = db == nullptr
              ? SqliteFailure(rc, _errstr(rc).toDartString())
              : SqliteFailure(_extendedErrcode(db), _errmsg(db).toDartString());
          if (db != nullptr) {
            _closeV2(db);
          }
          throw failure;
        }
        _extendedResultCodes(db, 1);
        return SqliteConnection._(this, db);
      });
}

/// One open connection, and the statements run on it.
class SqliteConnection {
  SqliteConnection._(this._lib, this._db);

  final Sqlite3Library _lib;
  final Pointer<Sqlite3> _db;
  bool _closed = false;

  /// Whether [close] has run.
  bool get isClosed => _closed;

  /// `sqlite3_changes`: rows changed by the last statement.
  int get changes => _lib._changes(_db);

  /// `sqlite3_last_insert_rowid`.
  int get lastInsertRowId => _lib._lastInsertRowId(_db);

  /// Whether no transaction is open (`sqlite3_get_autocommit`).
  bool get autocommit => _lib._getAutocommit(_db) != 0;

  SqliteFailure _failure() => SqliteFailure(
      _lib._extendedErrcode(_db), _lib._errmsg(_db).toDartString());

  /// Closes the connection. Statements still open are finalized first.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _lib._closeV2(_db);
  }

  /// Runs every statement in [sql], as `sqlite3_exec` would.
  void executeAll(String sql) {
    using((Arena arena) {
      final Uint8List bytes = utf8.encode(sql);
      final Pointer<Uint8> buffer = arena<Uint8>(bytes.length + 1);
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      buffer[bytes.length] = 0;
      final Pointer<Pointer<Sqlite3Statement>> out =
          arena<Pointer<Sqlite3Statement>>();
      final Pointer<Pointer<Uint8>> tail = arena<Pointer<Uint8>>();
      Pointer<Uint8> cursor = buffer;
      final int end = buffer.address + bytes.length;
      while (cursor.address < end) {
        final int remaining = end - cursor.address;
        if (_lib._prepareV2(_db, cursor, remaining, out, tail) !=
            SqliteCode.ok) {
          throw _failure();
        }
        final Pointer<Sqlite3Statement> statement = out.value;
        final Pointer<Uint8> next = tail.value;
        if (statement != nullptr) {
          try {
            int rc;
            do {
              rc = _lib._step(statement);
            } while (rc == SqliteCode.row);
            if (rc != SqliteCode.done) {
              throw _failure();
            }
          } finally {
            _lib._finalize(statement);
          }
        }
        if (next == nullptr || next.address <= cursor.address) {
          break;
        }
        cursor = next;
      }
    });
  }

  /// Prepares the first statement of [sql] and binds [arguments].
  SqliteStatement prepare(String sql, List<Object?> arguments) =>
      using((Arena arena) {
        final Uint8List bytes = utf8.encode(sql);
        final Pointer<Uint8> buffer = arena<Uint8>(bytes.length + 1);
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        buffer[bytes.length] = 0;
        final Pointer<Pointer<Sqlite3Statement>> out =
            arena<Pointer<Sqlite3Statement>>();
        if (_lib._prepareV2(_db, buffer, bytes.length, out, nullptr) !=
            SqliteCode.ok) {
          throw _failure();
        }
        final SqliteStatement statement = SqliteStatement._(this, out.value);
        try {
          statement._bind(arguments);
        } catch (_) {
          statement.close();
          rethrow;
        }
        return statement;
      });

  /// Runs [sql] with [arguments], discarding any rows.
  void execute(String sql, List<Object?> arguments) {
    final SqliteStatement statement = prepare(sql, arguments);
    try {
      while (statement.step()) {}
    } finally {
      statement.close();
    }
  }

  /// Runs [sql] with [arguments] and returns its columns and every row.
  ({List<String> columns, List<List<Object?>> rows}) select(
      String sql, List<Object?> arguments) {
    final SqliteStatement statement = prepare(sql, arguments);
    try {
      final List<List<Object?>> rows = <List<Object?>>[];
      while (statement.step()) {
        rows.add(statement.row());
      }
      return (columns: statement.columns, rows: rows);
    } finally {
      statement.close();
    }
  }
}

/// A prepared statement, stepped row by row.
class SqliteStatement {
  SqliteStatement._(this._connection, this._statement);

  final SqliteConnection _connection;
  final Pointer<Sqlite3Statement> _statement;
  bool _closed = false;

  Sqlite3Library get _lib => _connection._lib;

  void _check(int rc) {
    if (rc != SqliteCode.ok) {
      throw _connection._failure();
    }
  }

  void _bind(List<Object?> arguments) {
    if (_statement == nullptr) {
      // Only whitespace or a comment: nothing to bind, nothing to run.
      return;
    }
    final int count = _lib._bindParameterCount(_statement);
    if (arguments.length != count) {
      throw SqliteFailure(
          25, // SQLITE_RANGE
          'Expected $count arguments, got ${arguments.length}');
    }
    for (int i = 0; i < arguments.length; i++) {
      final int index = i + 1;
      final Object? value = arguments[i];
      switch (value) {
        case null:
          _check(_lib._bindNull(_statement, index));
        case int():
          _check(_lib._bindInt64(_statement, index, value));
        case double():
          _check(_lib._bindDouble(_statement, index, value));
        case BigInt():
          if (!value.isValidInt) {
            throw ArgumentError.value(
                value, 'arguments', 'does not fit in a 64-bit integer');
          }
          _check(_lib._bindInt64(_statement, index, value.toInt()));
        case String():
          using((Arena arena) {
            final Uint8List bytes = utf8.encode(value);
            final Pointer<Uint8> p =
                arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
            p.asTypedList(bytes.length).setAll(0, bytes);
            _check(
                _lib._bindText(_statement, index, p, bytes.length, _transient));
          });
        case Uint8List():
          if (value.isEmpty) {
            _check(_lib._bindZeroBlob(_statement, index, 0));
          } else {
            using((Arena arena) {
              final Pointer<Uint8> p = arena<Uint8>(value.length);
              p.asTypedList(value.length).setAll(0, value);
              _check(_lib._bindBlob(
                  _statement, index, p, value.length, _transient));
            });
          }
        default:
          throw ArgumentError(
              "Invalid sql argument type '${value.runtimeType}': $value");
      }
    }
  }

  /// The result column names.
  List<String> get columns => <String>[
        if (_statement != nullptr)
          for (int i = 0; i < _lib._columnCount(_statement); i++)
            _lib._columnName(_statement, i).toDartString(),
      ];

  /// Steps once: true when a row is ready, false when the statement is done.
  bool step() {
    if (_statement == nullptr) {
      return false;
    }
    final int rc = _lib._step(_statement);
    if (rc == SqliteCode.row) {
      return true;
    }
    if (rc == SqliteCode.done) {
      return false;
    }
    throw _connection._failure();
  }

  /// The current row's values: int, double, String, Uint8List or null.
  List<Object?> row() {
    final int count = _lib._columnCount(_statement);
    return <Object?>[
      for (int i = 0; i < count; i++) _value(i),
    ];
  }

  Object? _value(int i) {
    switch (_lib._columnType(_statement, i)) {
      case SqliteCode.typeInteger:
        return _lib._columnInt64(_statement, i);
      case SqliteCode.typeFloat:
        return _lib._columnDouble(_statement, i);
      case SqliteCode.typeText:
        final Pointer<Uint8> text = _lib._columnText(_statement, i);
        final int length = _lib._columnBytes(_statement, i);
        return text == nullptr
            ? ''
            : utf8.decode(text.asTypedList(length), allowMalformed: true);
      case SqliteCode.typeBlob:
        final Pointer<Uint8> blob = _lib._columnBlob(_statement, i);
        final int length = _lib._columnBytes(_statement, i);
        return blob == nullptr
            ? Uint8List(0)
            : Uint8List.fromList(blob.asTypedList(length));
      default:
        return null;
    }
  }

  /// Finalizes the statement.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    if (_statement != nullptr) {
      _lib._finalize(_statement);
    }
  }
}
