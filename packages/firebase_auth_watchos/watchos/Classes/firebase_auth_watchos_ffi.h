// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// C symbols exported to Dart over dart:ffi. Every function that returns a
// `const char *` returns a freshly heap-allocated UTF-8 JSON string; ownership
// transfers to the caller, which must release it with
// `firebase_auth_watchos_free`. Errors are reported in-band as
// `{"error": message, "code": code}`.
//
// Firebase Auth operations are network-backed, so the bridge is asynchronous:
// `firebase_auth_watchos_begin` starts an operation described by a JSON
// request and returns `{"token": N}`; the Dart side polls
// `firebase_auth_watchos_poll` with that token until the result replaces
// `{"pending": true}`. Cheap local reads (current user, sign-out, language
// code) are synchronous calls.

#ifndef FIREBASE_AUTH_WATCHOS_FFI_H
#define FIREBASE_AUTH_WATCHOS_FFI_H

#include <stdint.h>

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it. The watch
// app links this archive statically, so without the attributes the linker
// would drop these (FFI has no compile-time caller). The CLI additionally
// emits a forced reference for each symbol listed under
// `flutter.plugin.platforms.watchos.ffiSymbols`.
#define FIREBASE_AUTH_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// Starts an asynchronous auth operation. `request_json` is a JSON object with
// at least {"op": name, "app": dartAppName}; op-specific arguments ride along
// in the same object. Returns {"token": N} on acceptance, or an error object
// if the request is malformed or the app is not configured.
FIREBASE_AUTH_WATCHOS_EXPORT const char* firebase_auth_watchos_begin(
    const char* request_json);

// Polls an operation started by `firebase_auth_watchos_begin`. Returns
// {"pending": true} until the operation completes, then the operation's
// result object (or an in-band error object) exactly once.
FIREBASE_AUTH_WATCHOS_EXPORT const char* firebase_auth_watchos_poll(
    int64_t token);

// Returns the auth instance's current state:
// {"authGeneration": n, "idTokenGeneration": m, "user": {...} | null}.
// The generations increment on every native auth-state / ID-token change
// notification, letting the Dart side poll for changes cheaply.
FIREBASE_AUTH_WATCHOS_EXPORT const char* firebase_auth_watchos_current_user(
    const char* app_name);

// Signs out the current user synchronously. Returns {"ok": true} or an error.
FIREBASE_AUTH_WATCHOS_EXPORT const char* firebase_auth_watchos_sign_out(
    const char* app_name);

// Sets the auth language code. An empty `code` selects the device/app
// language (`useAppLanguage`). Returns {"languageCode": ... | null}.
FIREBASE_AUTH_WATCHOS_EXPORT const char* firebase_auth_watchos_set_language_code(
    const char* app_name, const char* code);

// Points the auth instance at a local Auth emulator. Returns {"ok": true}.
FIREBASE_AUTH_WATCHOS_EXPORT const char* firebase_auth_watchos_use_emulator(
    const char* app_name, const char* host, int64_t port);

// Returns {"value": bool} — whether `link` is a sign-in-with-email link.
FIREBASE_AUTH_WATCHOS_EXPORT const char* firebase_auth_watchos_is_sign_in_link(
    const char* app_name, const char* link);

// Releases a string previously returned by any of the functions above.
FIREBASE_AUTH_WATCHOS_EXPORT void firebase_auth_watchos_free(const char* ptr);

#endif  // FIREBASE_AUTH_WATCHOS_FFI_H
