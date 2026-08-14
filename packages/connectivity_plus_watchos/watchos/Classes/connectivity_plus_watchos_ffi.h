// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CONNECTIVITY_PLUS_WATCHOS_FFI_H
#define CONNECTIVITY_PLUS_WATCHOS_FFI_H

#include <stdint.h>

// See path_provider_watchos_ffi.h for why the exports are `used` +
// default-visibility. The CLI also emits a forced reference for each symbol
// listed under `flutter.plugin.platforms.watchos.ffiSymbols`.
#define CONNECTIVITY_PLUS_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// Connectivity codes (kept in sync with the Dart mapping):
//   0 = none, 1 = wifi, 2 = mobile (cellular), 3 = ethernet, 4 = other.
enum {
  kConnectivityWatchosNone = 0,
  kConnectivityWatchosWifi = 1,
  kConnectivityWatchosMobile = 2,
  kConnectivityWatchosEthernet = 3,
  kConnectivityWatchosOther = 4,
};

/// Called from the `NWPathMonitor` queue when connectivity changes.
///
/// Carries no value: the callback is a `NativeCallable.listener`, which runs
/// asynchronously, so anything passed by pointer could be stale or freed by
/// the time Dart reads it. Dart re-reads `..._current` instead.
typedef void (*connectivity_plus_watchos_cb)(int64_t unused);

/// Registers the function to wake Dart on a change, or NULL to stop.
///
/// Starts the monitor if it is not already running, so a listener registered
/// before the first `..._current` call still gets updates.
CONNECTIVITY_PLUS_WATCHOS_EXPORT void connectivity_plus_watchos_set_callback(
    connectivity_plus_watchos_cb callback);

/// Current connectivity code. On the first call this starts a persistent
/// `NWPathMonitor` on a background queue; subsequent calls read the latest
/// path status it has cached.
CONNECTIVITY_PLUS_WATCHOS_EXPORT int32_t connectivity_plus_watchos_current(void);

#endif  // CONNECTIVITY_PLUS_WATCHOS_FFI_H
