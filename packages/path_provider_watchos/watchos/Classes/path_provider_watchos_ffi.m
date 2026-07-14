// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "path_provider_watchos_ffi.h"

#import <Foundation/Foundation.h>

#include <stdlib.h>
#include <string.h>

// Sandbox directory paths are constant for the lifetime of the process, so
// each getter resolves once and caches a heap copy. `strdup` never gets
// freed by design — one small allocation per directory, owned by the plugin,
// so Dart can treat the pointers as static strings.
static const char* _cached_path(NSSearchPathDirectory directory, BOOL create) {
    @autoreleasepool {
        NSURL* url = [[NSFileManager defaultManager] URLForDirectory:directory
                                                             inDomain:NSUserDomainMask
                                                    appropriateForURL:nil
                                                               create:create
                                                                error:nil];
        if (url == nil || url.path == nil) {
            return NULL;
        }
        return strdup(url.path.UTF8String);
    }
}

const char* path_provider_watchos_temporary_path(void) {
    static const char* path = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @autoreleasepool {
            NSString* tmp = NSTemporaryDirectory();
            if (tmp != nil) {
                // Strip the trailing slash NSTemporaryDirectory() appends so the
                // result matches the other getters' shape.
                NSString* normalized = [tmp length] > 1 && [tmp hasSuffix:@"/"]
                    ? [tmp substringToIndex:[tmp length] - 1]
                    : tmp;
                path = strdup(normalized.UTF8String);
            }
        }
    });
    return path;
}

const char* path_provider_watchos_application_support_path(void) {
    static const char* path = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // create:YES — Application Support does not exist by default in the
        // sandbox; iOS path_provider creates it too.
        path = _cached_path(NSApplicationSupportDirectory, YES);
    });
    return path;
}

const char* path_provider_watchos_library_path(void) {
    static const char* path = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        path = _cached_path(NSLibraryDirectory, NO);
    });
    return path;
}

const char* path_provider_watchos_documents_path(void) {
    static const char* path = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        path = _cached_path(NSDocumentDirectory, NO);
    });
    return path;
}

const char* path_provider_watchos_cache_path(void) {
    static const char* path = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        path = _cached_path(NSCachesDirectory, NO);
    });
    return path;
}
