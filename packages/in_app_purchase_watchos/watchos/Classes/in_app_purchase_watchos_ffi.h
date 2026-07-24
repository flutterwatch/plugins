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

// Whether this device/account can make payments (`SKPaymentQueue
// canMakePayments`) — false when purchases are disallowed, e.g. by parental
// restrictions. Backs `InAppPurchase.isAvailable()`, which apps call before
// anything else.
IN_APP_PURCHASE_WATCHOS_EXPORT bool in_app_purchase_watchos_can_make_payments(void);

// Purchase flow (StoreKit `SKPaymentQueue`).
//
// Install the transaction observer once, then drive purchases: buy() enqueues a
// payment for a product a prior query cached; the observer records every
// transaction update, which Dart pulls with purchases_drain() and feeds to
// `purchaseStream`. finish() completes a transaction; restore() replays past
// non-consumable/subscription purchases. Like the query, updates are async, so
// the model is again install → poll(drain) → act.

// Installs the SKPaymentQueue transaction observer (idempotent). Safe to call
// from registerWith so transactions pending at launch are captured.
IN_APP_PURCHASE_WATCHOS_EXPORT void in_app_purchase_watchos_purchases_start(void);

// Enqueues a payment for [product_id] — which must have been returned by a
// prior ..._query_* (whose SKProduct the plugin caches). [application_username]
// may be empty; [quantity] >= 1. Returns false if the product was not cached
// (query it first).
IN_APP_PURCHASE_WATCHOS_EXPORT bool in_app_purchase_watchos_buy(
    const char* product_id, const char* application_username, int32_t quantity);

// Returns pending transaction updates as a UTF-8 JSON array and clears the
// buffer. Plugin-owned; valid until the next drain call. Each element:
//   {"productID","purchaseID","transactionDate","status","receipt","error"?}
// where status is: purchasing | purchased | failed | restored | deferred, and
// error (only on failed) is {"code","message","canceled"}.
IN_APP_PURCHASE_WATCHOS_EXPORT const char* in_app_purchase_watchos_purchases_drain(void);

// Finishes the transaction with [purchase_id] (the update's "purchaseID").
// No-op for an unknown id.
IN_APP_PURCHASE_WATCHOS_EXPORT void in_app_purchase_watchos_finish(const char* purchase_id);

// Restores completed non-consumable/subscription purchases; the restored
// transactions arrive via purchases_drain with status "restored".
IN_APP_PURCHASE_WATCHOS_EXPORT void in_app_purchase_watchos_restore(
    const char* application_username);

#endif  // IN_APP_PURCHASE_WATCHOS_FFI_H
