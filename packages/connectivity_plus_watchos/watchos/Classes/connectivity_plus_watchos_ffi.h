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

/// Current connectivity code. On the first call this starts a persistent
/// `NWPathMonitor` on a background queue; subsequent calls read the latest
/// path status it has cached. The Dart side polls this for the change
/// stream, since watchOS has no cross-FFI push channel.
CONNECTIVITY_PLUS_WATCHOS_EXPORT int32_t connectivity_plus_watchos_current(void);

#endif  // CONNECTIVITY_PLUS_WATCHOS_FFI_H
