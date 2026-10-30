// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The host's system SQLite, which the host tests run real SQL on. The
// background isolate opens it by path, since a DynamicLibrary cannot be sent
// to another isolate; tests of the handler itself open it here.

import 'dart:ffi';
import 'dart:io';

/// The host's system SQLite: `/usr/lib` on macOS, the shared library's
/// soname on Linux.
String get hostSqlitePath =>
    Platform.isMacOS ? '/usr/lib/libsqlite3.dylib' : 'libsqlite3.so.0';

/// The host's system SQLite, opened on the calling isolate.
DynamicLibrary hostSqlite() => DynamicLibrary.open(hostSqlitePath);
