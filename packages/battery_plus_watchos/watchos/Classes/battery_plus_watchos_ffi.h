// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef BATTERY_PLUS_WATCHOS_FFI_H
#define BATTERY_PLUS_WATCHOS_FFI_H

#include <stdint.h>

// See path_provider_watchos_ffi.h for why every symbol is `used` +
// default-visibility. The CLI also emits a forced reference for each symbol
// listed under `flutter.plugin.platforms.watchos.ffiSymbols`.
#define BATTERY_PLUS_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

/// Battery charge as a whole percentage 0–100, or -1 when unavailable
/// (`WKInterfaceDevice` reports -1 before battery monitoring is enabled or
/// on some simulators).
BATTERY_PLUS_WATCHOS_EXPORT int32_t battery_plus_watchos_level(void);

/// Charging state, using `WKInterfaceDeviceBatteryState` raw values:
/// 0 = unknown, 1 = unplugged (discharging), 2 = charging, 3 = full.
BATTERY_PLUS_WATCHOS_EXPORT int32_t battery_plus_watchos_state(void);

/// 1 when Low Power Mode is enabled (watchOS 9+), else 0.
BATTERY_PLUS_WATCHOS_EXPORT int32_t battery_plus_watchos_is_low_power(void);

#endif  // BATTERY_PLUS_WATCHOS_FFI_H
