// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `sqflite`, over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so sqflite's method
// protocol is answered in Dart (`src/handler.dart`) over the system SQLite's
// C API (`src/sqlite3.dart`). sqflite federates through sqflite_common's
// default database factory: `registerWith` sets it, as sqflite_darwin, which
// also extends SqflitePlatform, does with its method-channel factory.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
// ignore: implementation_imports
import 'package:sqflite_common/src/mixin/factory.dart'
    show buildDatabaseFactory;
import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_platform_interface/sqflite_platform_interface.dart';

import 'src/handler.dart';
import 'src/sqlite3.dart';

/// watchOS implementation of `sqflite`.
class SqfliteWatchos extends SqflitePlatform {
  /// Test hook: the library SQLite's C API resolves from, instead of the
  /// process. Host tests pass the host's system SQLite.
  static DynamicLibrary? libraryOverride;

  /// Test hook: where relative database paths live, instead of the app's
  /// Documents directory.
  static String? databasesPathOverride;

  static DatabaseFactory? _factory;

  /// The database factory that answers sqflite's calls on the watch, as
  /// [SqflitePlatform.databaseFactoryMethodChannel] answers them on iOS.
  static DatabaseFactory get databaseFactoryWatchos => _factory ??= () {
        final DynamicLibrary library =
            libraryOverride ?? DynamicLibrary.process();
        final SqfliteWatchosHandler handler = SqfliteWatchosHandler(
          Sqlite3Library(library),
          databasesPath: databasesPathOverride ?? _databasesPath(library),
          platformVersion: 'watchOS ${Platform.operatingSystemVersion}',
        );
        return buildDatabaseFactory(
          tag: 'watchos',
          invokeMethod: handler.handle,
        );
      }();

  /// Registers this implementation as sqflite's default database factory on
  /// watchOS, unless the app already set one.
  static void registerWith() {
    databaseFactoryOrNull ??= databaseFactoryWatchos;
  }

  /// Forgets the factory so the next use builds a new one, for tests that
  /// change [libraryOverride] or [databasesPathOverride].
  static void resetForTesting() => _factory = null;

  static String _databasesPath(DynamicLibrary library) => library
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'sqflite_watchos_databases_path')()
      .toDartString();

  /// The version of the SQLite the watch runs, for example `3.46.1`.
  static String get sqliteVersion =>
      (libraryOverride ?? DynamicLibrary.process())
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
              libraryOverride == null
                  ? 'sqflite_watchos_sqlite_version'
                  : 'sqlite3_libversion')()
          .toDartString();
}
