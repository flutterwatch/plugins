// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FIREBASE_CORE_WATCHOS_FFI_H
#define FIREBASE_CORE_WATCHOS_FFI_H

#include <stdbool.h>  // `bool` in the C ABI these symbols export

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it. The watch
// app links this archive statically, so without `used` the linker would drop
// these (FFI has no compile-time caller). The flutter-watchos CLI
// additionally emits a forced reference for each symbol listed under
// `flutter.plugin.platforms.watchos.ffiSymbols` in pubspec.yaml.
#define FIREBASE_CORE_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// String results are heap-allocated UTF-8 JSON built per call; the caller
// copies the value into Dart and then releases it with
// `firebase_core_watchos_free`. A NULL result means out-of-memory only —
// errors are reported in-band as a JSON object with an `"error"` key.

/// Configures a Firebase app.
///
/// `name` is the Dart-side app name; the empty string (or "[DEFAULT]") means
/// the default app. `options_json` is the JSON form of `FirebaseOptions.asMap`
/// (see the Dart side); the empty string configures the default app from a
/// bundled `GoogleService-Info.plist` instead.
///
/// Returns a JSON object: on success
/// `{"name":..,"options":{..},"isAutomaticDataCollectionEnabled":bool}`;
/// on failure `{"error":"..","code":".."}`. Configuring an already-configured
/// app with matching options is treated as success (idempotent), matching the
/// FlutterFire behaviour.
FIREBASE_CORE_WATCHOS_EXPORT const char* firebase_core_watchos_configure(
    const char* name, const char* options_json);

/// Returns the JSON app-info object for an already-configured app, or
/// `{"error":..}` if no such app exists. Used to read back the default app
/// that a bundled plist configured.
FIREBASE_CORE_WATCHOS_EXPORT const char* firebase_core_watchos_options(
    const char* name);

/// Returns a JSON array of app-info objects for every configured app.
FIREBASE_CORE_WATCHOS_EXPORT const char* firebase_core_watchos_apps(void);

/// Deletes a configured app. Returns `{"deleted":true}` or `{"error":..}`.
/// Deleting the default app is a no-op that reports success (the Apple SDK
/// forbids it), matching FlutterFire.
FIREBASE_CORE_WATCHOS_EXPORT const char* firebase_core_watchos_delete(
    const char* name);

/// Sets whether automatic data collection is enabled for the named app.
/// Returns `{"ok":true}` or `{"error":..}`.
FIREBASE_CORE_WATCHOS_EXPORT const char* firebase_core_watchos_set_auto_data_collection(
    const char* name, bool enabled);

/// Frees a string previously returned by any function above.
FIREBASE_CORE_WATCHOS_EXPORT void firebase_core_watchos_free(const char* ptr);

#endif  // FIREBASE_CORE_WATCHOS_FFI_H
