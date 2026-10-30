// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `sqflite`, over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so sqflite's method
// protocol is answered in Dart (`src/handler.dart`) over the system SQLite's
// C API (`src/sqlite3.dart`), on a background isolate (`src/worker.dart`).
// sqflite federates through sqflite_common's default database factory:
// `registerWith` sets it, as sqflite_darwin, which also extends
// SqflitePlatform, does with its method-channel factory.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
// ignore: implementation_imports
import 'package:sqflite_common/src/mixin/factory.dart'
    show buildDatabaseFactory;
import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_platform_interface/sqflite_platform_interface.dart';

import 'src/worker.dart';

/// watchOS implementation of `sqflite`.
class SqfliteWatchos extends SqflitePlatform {
  /// Test hook: the path of the SQLite library the background isolate
  /// opens, instead of resolving SQLite's C API from the process. Host tests
  /// pass the host's system SQLite. It is a path because a [DynamicLibrary]
  /// cannot be sent to another isolate.
  static String? libraryPathOverride;

  /// Test hook: where relative database paths live, instead of the app's
  /// Documents directory.
  static String? databasesPathOverride;

  static SqfliteWatchosWorker? _worker;
  static DatabaseFactory? _factory;

  /// The database factory that answers sqflite's calls on the watch, as
  /// [SqflitePlatform.databaseFactoryMethodChannel] answers them on iOS.
  ///
  /// Its calls run on a background isolate, which the first call starts and
  /// every database the factory opens shares.
  static DatabaseFactory get databaseFactoryWatchos => _factory ??= () {
        final SqfliteWatchosWorker worker = _worker = SqfliteWatchosWorker(
          libraryPath: libraryPathOverride,
          databasesPath: databasesPathOverride,
        );
        return buildDatabaseFactory(
          tag: 'watchos',
          invokeMethod: worker.invoke,
        );
      }();

  /// Registers this implementation as sqflite's default database factory on
  /// watchOS, unless the app already set one.
  static void registerWith() {
    databaseFactoryOrNull ??= databaseFactoryWatchos;
  }

  /// Forgets the factory so the next use builds a new one, for tests that
  /// change [libraryPathOverride] or [databasesPathOverride].
  ///
  /// The old factory's isolate answers the calls already made, closes every
  /// database it has open and ends. The future completes once it has ended.
  /// Calls on the old factory then fail.
  static Future<void> resetForTesting() {
    final SqfliteWatchosWorker? worker = _worker;
    _worker = null;
    _factory = null;
    return worker?.stop() ?? Future<void>.value();
  }

  /// The version of the SQLite the watch runs, for example `3.46.1`. It is
  /// read on the calling isolate.
  static String get sqliteVersion {
    final String? path = libraryPathOverride;
    return (path == null ? DynamicLibrary.process() : DynamicLibrary.open(path))
        .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            path == null
                ? 'sqflite_watchos_sqlite_version'
                : 'sqlite3_libversion')()
        .toDartString();
  }
}
