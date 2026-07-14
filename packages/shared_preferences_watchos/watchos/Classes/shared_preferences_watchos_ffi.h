// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef SHARED_PREFERENCES_WATCHOS_FFI_H
#define SHARED_PREFERENCES_WATCHOS_FFI_H

// See path_provider_watchos_ffi.h for why every symbol is `used` +
// default-visibility. The CLI also emits a forced reference for each symbol
// listed under `flutter.plugin.platforms.watchos.ffiSymbols`.
#define SHARED_PREFERENCES_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// The store is a single JSON object persisted in NSUserDefaults under one
// private key. Native side is deliberately dumb: it only loads and saves the
// blob; all typing, filtering and prefixing live in Dart. This isolates the
// plugin's data from system NSUserDefaults keys and makes get-all trivial.

/// Returns the persisted store as a JSON object string (`{}` when empty).
/// The buffer is malloc'd fresh on every call — the caller MUST release it
/// with `shared_preferences_watchos_free`.
SHARED_PREFERENCES_WATCHOS_EXPORT const char* shared_preferences_watchos_load(void);

/// Persists [json] (a JSON object string) as the whole store.
SHARED_PREFERENCES_WATCHOS_EXPORT void shared_preferences_watchos_save(const char* json);

/// Frees a buffer returned by `shared_preferences_watchos_load`.
SHARED_PREFERENCES_WATCHOS_EXPORT void shared_preferences_watchos_free(char* ptr);

#endif  // SHARED_PREFERENCES_WATCHOS_FFI_H
