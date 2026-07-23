// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of in_app_purchase, over dart:ffi.
// Source plugin: in_app_purchase_storekit. See PORTING_REPORT.md.

#ifndef IN_APP_PURCHASE_WATCHOS_FFI_H
#define IN_APP_PURCHASE_WATCHOS_FFI_H

#include <stdbool.h>
#include <stdint.h>

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it. The watch
// app links this archive statically, so without the attributes the linker
// would drop these (FFI has no compile-time caller). The CLI additionally
// emits a forced reference for each symbol listed under
// `flutter.plugin.platforms.watchos.ffiSymbols`.
#define IN_APP_PURCHASE_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// Product-details query (StoreKit `SKProductsRequest`).
//
// StoreKit's product lookup is asynchronous, but dart:ffi calls are
// synchronous, so the query is exposed as start -> poll -> read -> release:
//
//   int64_t h = ..._query_start(ids_json);   // kick off; 0 == couldn't start
//   while (!..._query_ready(h)) { /* Dart awaits a short delay */ }
//   const char *json = ..._query_result(h);  // owned by the plugin
//   ..._query_release(h);                     // frees the result + handle
//
// [ids_json] is a UTF-8 JSON array of product identifiers, e.g. `["a","b"]`.
// The result is a UTF-8 JSON object:
//   {"products":[{"id","title","description","price","rawPrice",
//                 "currencyCode","currencySymbol"}...],
//    "notFound":["id"...],
//    "error":{"code","message"}?}
// The returned pointer stays valid until ..._query_release(h); Dart copies it
// out immediately and never frees it.

IN_APP_PURCHASE_WATCHOS_EXPORT int64_t
in_app_purchase_watchos_query_start(const char* ids_json);

IN_APP_PURCHASE_WATCHOS_EXPORT bool
in_app_purchase_watchos_query_ready(int64_t handle);

IN_APP_PURCHASE_WATCHOS_EXPORT const char*
in_app_purchase_watchos_query_result(int64_t handle);

IN_APP_PURCHASE_WATCHOS_EXPORT void
in_app_purchase_watchos_query_release(int64_t handle);

#endif  // IN_APP_PURCHASE_WATCHOS_FFI_H
