// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The two native helpers sqflite_watchos needs; see the header. Everything
// else is libsqlite3's own C API, called from Dart.

#import "sqflite_watchos_ffi.h"

#import <Foundation/Foundation.h>
#import <sqlite3.h>

const char* sqflite_watchos_databases_path(void) {
    static NSString* path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        path = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                   NSUserDomainMask, YES)
                   .firstObject;
        if (path == nil) {
            path = NSTemporaryDirectory();
        }
    });
    // `path` is never released, so its UTF-8 buffer stays valid.
    return path.fileSystemRepresentation;
}

const char* sqflite_watchos_sqlite_version(void) {
    return sqlite3_libversion();
}
