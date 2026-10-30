// Copyright (c) 2019, Alexandre Roux Tekartik. All rights reserved.
// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the BSD 2-Clause license that can
// be found in the LICENSE file.
//
// The background isolate that runs sqflite's method protocol, and the
// calling isolate's side of it.
//
// Adapted from sqflite_common_ffi's lib/src/isolate_io.dart and
// lib/src/method_call.dart, the model its databaseFactoryFfi runs on: one
// long-lived isolate, started by the first call and shared by every
// database, whose first message is the port it listens on; each call
// answered without waiting for the one before it, so that a call queued
// behind a transaction does not hold up the call that ends it; and errors
// that cross as data and are built again on the caller's side. Here every
// answer comes back on one port, matched by an id, an error that is not
// sqflite's is copied as it is, as Isolate.run copies one, and a stop
// closes every database before the isolate ends.
//
// A DynamicLibrary cannot be sent to another isolate, so the isolate binds
// SQLite itself: from the process on the watch, or from a path in host
// tests.

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
// ignore: implementation_imports
import 'package:sqflite_common/src/exception.dart'
    show SqfliteDatabaseException;

import 'handler.dart';
import 'sqlite3.dart';

/// Runs sqflite's method calls on a background isolate of its own.
class SqfliteWatchosWorker {
  /// A worker whose isolate binds SQLite from the library at [libraryPath],
  /// or from the process when it is null, and keeps relative paths under
  /// [databasesPath], or under the app's Documents directory when it is
  /// null. The isolate starts on the first call.
  SqfliteWatchosWorker({this.libraryPath, this.databasesPath});

  /// The SQLite library the isolate opens, or null for the process's.
  final String? libraryPath;

  /// Where relative database paths live, or null for the app's Documents
  /// directory.
  final String? databasesPath;

  ReceivePort? _answers;
  SendPort? _calls;

  /// What was posted before the isolate sent its port, in order.
  final List<Object> _unsent = <Object>[];

  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  int _lastId = 0;

  /// Why every call fails from now on: set once the isolate is stopping or
  /// has ended.
  String? _closed;

  /// An error the isolate did not catch, which it reports before it ends.
  String? _uncaught;

  final Completer<void> _ended = Completer<void>();

  /// Runs [method] with [arguments] on the isolate, starting it on the first
  /// call, and completes with what the handler answered.
  Future<Object?> invoke(String method, [Object? arguments]) {
    final String? closed = _closed;
    if (closed != null) {
      return Future<Object?>.error(_closedError(closed));
    }
    final int id = ++_lastId;
    final Completer<Object?> completer = Completer<Object?>();
    _pending[id] = completer;
    _post(_Call(id, method, arguments));
    return completer.future;
  }

  /// Stops the isolate once it has answered the calls already made. It
  /// closes every database it has open first, and what is queued behind a
  /// transaction fails. The future completes when the isolate has ended.
  /// Calls made after this one fail.
  Future<void> stop() {
    if (_closed == null) {
      _closed = 'the sqflite_watchos isolate was stopped';
      if (_answers == null) {
        // It never started.
        _ended.complete();
      } else {
        _post(const _Stop());
      }
    }
    return _ended.future;
  }

  void _post(Object message) {
    final SendPort? calls = _calls;
    if (calls == null) {
      _unsent.add(message);
      _start();
    } else {
      _send(calls, message);
    }
  }

  void _start() {
    if (_answers != null) {
      return;
    }
    final ReceivePort answers =
        _answers = ReceivePort('sqflite_watchos answers');
    answers.listen(_receive);
    Isolate.spawn<_Start>(
      _main,
      _Start(answers.sendPort, libraryPath, databasesPath),
      onExit: answers.sendPort,
      onError: answers.sendPort,
      debugName: 'sqflite_watchos',
    ).then<void>((Isolate _) {}, onError: (Object error) {
      _closed ??= 'the sqflite_watchos isolate did not start: $error';
      _end();
    });
  }

  void _send(SendPort calls, Object message) {
    try {
      calls.send(message);
    } catch (error, stack) {
      // An argument the VM cannot copy to another isolate. Its call fails as
      // a call with an argument the handler cannot bind does.
      if (message is _Call) {
        _pending
            .remove(message.id)
            ?.completeError(_unsendable(error, message.arguments), stack);
      }
    }
  }

  void _receive(Object? message) {
    switch (message) {
      case final SendPort calls:
        _calls = calls;
        for (final Object unsent in _unsent) {
          _send(calls, unsent);
        }
        _unsent.clear();
      case final _Answer answer:
        final Completer<Object?>? completer = _pending.remove(answer.id);
        final Object? error = answer.error;
        if (completer == null) {
          return;
        }
        if (error == null) {
          completer.complete(answer.result);
        } else {
          completer.completeError(
            error is _SqfliteError ? error.exception() : error,
            answer.stack,
          );
        }
      case [final Object? error, _]:
        // What Isolate.spawn's onError sends: the error's text and its
        // stack's.
        _uncaught ??= '$error';
      case null:
        // What Isolate.spawn's onExit sends, after every answer.
        _end();
    }
  }

  /// Fails every call the isolate did not answer, once it has ended.
  void _end() {
    _answers?.close();
    _calls = null;
    _unsent.clear();
    final String closed = _closed ??= _uncaught == null
        ? 'the sqflite_watchos isolate ended'
        : 'the sqflite_watchos isolate ended: $_uncaught';
    final List<Completer<Object?>> waiting = _pending.values.toList();
    _pending.clear();
    for (final Completer<Object?> completer in waiting) {
      completer.completeError(_closedError(closed));
    }
    if (!_ended.isCompleted) {
      _ended.complete();
    }
  }

  /// The error of a call the isolate will not answer. Every database it had
  /// open is closed, and isDatabaseClosedError() looks for database_closed.
  static SqfliteDatabaseException _closedError(String reason) =>
      SqfliteDatabaseException('database_closed: $reason', null);

  /// The error of a call whose arguments cannot be sent, with the details
  /// the handler gives a call it cannot bind.
  static SqfliteDatabaseException _unsendable(Object error, Object? arguments) {
    final Map<String, Object?> details = <String, Object?>{
      if (arguments is Map<Object?, Object?> && arguments['sql'] != null)
        'sql': arguments['sql'],
      if (arguments is Map<Object?, Object?> && arguments['arguments'] != null)
        'arguments': arguments['arguments'],
    };
    return SqfliteDatabaseException('$error', details.isEmpty ? null : details);
  }
}

/// What the isolate starts from.
final class _Start {
  const _Start(this.answers, this.libraryPath, this.databasesPath);

  final SendPort answers;
  final String? libraryPath;
  final String? databasesPath;
}

/// One method call, as the isolate receives it.
final class _Call {
  const _Call(this.id, this.method, this.arguments);

  final int id;
  final String method;
  final Object? arguments;
}

/// Asks the isolate to close its databases and end.
final class _Stop {
  const _Stop();
}

/// What a call answered: its result, or the error it failed with.
final class _Answer {
  _Answer.result(this.id, this.result)
      : error = null,
        stack = null;

  /// A SqfliteDatabaseException crosses as data. Any other error crosses as
  /// it is: isolates of one group copy it with its type.
  _Answer.error(this.id, Object thrown, StackTrace this.stack)
      : result = null,
        error =
            thrown is SqfliteDatabaseException ? _SqfliteError(thrown) : thrown;

  final int id;
  final Object? result;
  final Object? error;
  final StackTrace? stack;
}

/// A SqfliteDatabaseException as data: the fields sqflite_common reads.
final class _SqfliteError {
  _SqfliteError(SqfliteDatabaseException e)
      : message = e.message,
        details = e.result,
        resultCode = e.getResultCode(),
        transactionClosed = e.transactionClosed;

  final String? message;
  final Object? details;
  final int? resultCode;
  final bool transactionClosed;

  /// The exception again, on the caller's side.
  SqfliteDatabaseException exception() => SqfliteDatabaseException(
        message,
        details,
        resultCode: resultCode,
        transactionClosed: transactionClosed,
      );
}

/// The handler over the SQLite that [start] names, or what kept SQLite from
/// being bound.
({SqfliteWatchosHandler? handler, Object? error, StackTrace? stack}) _bind(
    _Start start) {
  try {
    final String? path = start.libraryPath;
    final DynamicLibrary library =
        path == null ? DynamicLibrary.process() : DynamicLibrary.open(path);
    final SqfliteWatchosHandler handler = SqfliteWatchosHandler(
      Sqlite3Library(library),
      databasesPath: start.databasesPath ?? _documentsPath(library),
      platformVersion: 'watchOS ${Platform.operatingSystemVersion}',
    );
    return (handler: handler, error: null, stack: null);
  } catch (error, stack) {
    return (handler: null, error: error, stack: stack);
  }
}

String _documentsPath(DynamicLibrary library) => library
    .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'sqflite_watchos_databases_path')()
    .toDartString();

/// The isolate: binds SQLite, sends the port it listens on, then answers
/// calls until it is stopped.
void _main(_Start start) {
  final (
    :SqfliteWatchosHandler? handler,
    :Object? error,
    :StackTrace? stack,
  ) = _bind(start);
  final ReceivePort calls = ReceivePort('sqflite_watchos calls');
  calls.listen((Object? message) {
    if (message is! _Call) {
      // The stop, which comes after every call made before it.
      handler?.closeAll();
      calls.close();
      return;
    }
    // A SQLite that could not be bound fails every call, as it once failed
    // the factory.
    final Future<Object?> result = handler == null
        ? Future<Object?>.error(error!, stack)
        : handler.handle(message.method, message.arguments);
    // Not awaited: a call queued behind a transaction waits for later calls.
    unawaited(result.then(
      (Object? value) =>
          _answer(start.answers, _Answer.result(message.id, value)),
      onError: (Object thrown, StackTrace trace) =>
          _answer(start.answers, _Answer.error(message.id, thrown, trace)),
    ));
  });
  start.answers.send(calls.sendPort);
}

/// Sends [answer]. An error the VM cannot copy goes as a RemoteError with its
/// text, as Isolate.run sends one.
void _answer(SendPort answers, _Answer answer) {
  try {
    answers.send(answer);
  } catch (sendError) {
    final Object? error = answer.error;
    final RemoteError remote = RemoteError(
      error is _SqfliteError ? '${error.exception()}' : '${error ?? sendError}',
      '${answer.stack ?? ''}',
    );
    answers.send(_Answer.error(answer.id, remote, remote.stackTrace));
  }
}
