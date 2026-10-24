// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `sqflite`, over dart:ffi.
//
// SQLite itself is the system library: watchOS ships libsqlite3, the CLI links
// it (`.linkedLibrary("sqlite3")` in Package.swift), and Dart calls its C API
// directly through `DynamicLibrary.process()`. This file adds only what
// SQLite does not have: where databases live, and a call into libsqlite3
// that keeps the library linked into the watch binary.

#ifndef SQFLITE_WATCHOS_FFI_H
#define SQFLITE_WATCHOS_FFI_H

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it.
#define SQFLITE_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// The app's Documents directory, where sqflite keeps databases on iOS too.
// The string is owned by this file and lives as long as the app.
SQFLITE_WATCHOS_EXPORT
const char* sqflite_watchos_databases_path(void);

// sqlite3_libversion(), for example "3.46.1". Also what keeps libsqlite3
// linked: the binary references it from here.
SQFLITE_WATCHOS_EXPORT
const char* sqflite_watchos_sqlite_version(void);

#endif  // SQFLITE_WATCHOS_FFI_H
