// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// C symbols exported to Dart over dart:ffi. Every function that returns a
// `const char *` returns a freshly heap-allocated UTF-8 JSON string; ownership
// transfers to the caller, which must release it with
// `firebase_storage_watchos_free`. Errors are reported in-band as
// `{"error": message, "code": code}`.
//
// Storage operations are network-backed, so the bridge is asynchronous:
// one-shot operations go through `firebase_storage_watchos_begin` +
// `firebase_storage_watchos_poll` (same pattern as firebase_auth_watchos),
// while uploads/downloads are long-lived tasks started with
// `firebase_storage_watchos_task_start` whose progress the Dart side reads
// with `firebase_storage_watchos_task_snapshot`.

#ifndef FIREBASE_STORAGE_WATCHOS_FFI_H
#define FIREBASE_STORAGE_WATCHOS_FFI_H

#include <stdint.h>

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it. The watch
// app links this archive statically, so without the attributes the linker
// would drop these (FFI has no compile-time caller). The CLI additionally
// emits a forced reference for each symbol listed under
// `flutter.plugin.platforms.watchos.ffiSymbols`.
#define FIREBASE_STORAGE_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// Starts an asynchronous one-shot operation. `request_json` is a JSON object
// with at least {"op": name, "app": dartAppName, "bucket": bucket}; the
// reference path and op-specific arguments ride along in the same object.
// Returns {"token": N} on acceptance, or an error object.
FIREBASE_STORAGE_WATCHOS_EXPORT const char* firebase_storage_watchos_begin(
    const char* request_json);

// Polls an operation started by `firebase_storage_watchos_begin`. Returns
// {"pending": true} until the operation completes, then the operation's
// result object (or an in-band error object) exactly once.
FIREBASE_STORAGE_WATCHOS_EXPORT const char* firebase_storage_watchos_poll(
    int64_t token);

// Starts an upload or download task. `request_json` carries
// {"kind": "putData"|"putFile"|"writeToFile", "app", "bucket", "path",
//  "data" (base64, putData) | "filePath", "metadata"? {...}}.
// Returns {"taskId": N} or an error object.
FIREBASE_STORAGE_WATCHOS_EXPORT const char* firebase_storage_watchos_task_start(
    const char* request_json);

// Reads a task's latest snapshot:
// {"state": "running"|"paused"|"success"|"canceled"|"error",
//  "bytesTransferred": n, "totalBytes": n,
//  "metadata": {...} (uploads, on success),
//  "error": {...} (state == error/canceled)}.
FIREBASE_STORAGE_WATCHOS_EXPORT const char* firebase_storage_watchos_task_snapshot(
    int64_t task_id);

// Controls a task: `action` is "pause", "resume", or "cancel".
// Returns {"value": bool}.
FIREBASE_STORAGE_WATCHOS_EXPORT const char* firebase_storage_watchos_task_control(
    int64_t task_id, const char* action);

// Synchronous per-instance configuration:
// {"op": "useEmulator", "host", "port"} or
// {"op": "setMaxOperationRetryTime"|"setMaxUploadRetryTime"|
//        "setMaxDownloadRetryTime", "milliseconds": n}.
// Returns {"ok": true} or an error object.
FIREBASE_STORAGE_WATCHOS_EXPORT const char* firebase_storage_watchos_configure(
    const char* request_json);

// Releases a string previously returned by any of the functions above.
FIREBASE_STORAGE_WATCHOS_EXPORT void firebase_storage_watchos_free(
    const char* ptr);

#endif  // FIREBASE_STORAGE_WATCHOS_FFI_H
