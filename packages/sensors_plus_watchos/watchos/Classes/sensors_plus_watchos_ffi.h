// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `sensors_plus`, over dart:ffi.
//
// CoreMotion (CMMotionManager) delivers samples asynchronously; each `start_*`
// begins updates into a cached latest value, `read_*` copies that value into a
// caller-owned 3-double buffer (x, y, z), and `stop_*` ends updates. The Dart
// side polls `read_*` on a timer at the requested sampling period.
//
// Note: the watchOS Simulator has no motion hardware, so on the Simulator the
// sensors report unavailable and `read_*` yields no data; on a real Apple
// Watch the accelerometer, gyroscope and magnetometer stream normally.

#ifndef SENSORS_PLUS_WATCHOS_FFI_H
#define SENSORS_PLUS_WATCHOS_FFI_H

#include <stdint.h>

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it.
#define SENSORS_PLUS_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// `read_*` fills out_xyz[0..2] and returns 1 when a sample is available, 0
// otherwise. `interval_micros` is the requested update period in microseconds.

SENSORS_PLUS_WATCHOS_EXPORT
void sensors_plus_watchos_start_accelerometer(int64_t interval_micros);
SENSORS_PLUS_WATCHOS_EXPORT
int sensors_plus_watchos_read_accelerometer(double* out_xyz);
SENSORS_PLUS_WATCHOS_EXPORT
void sensors_plus_watchos_stop_accelerometer(void);

SENSORS_PLUS_WATCHOS_EXPORT
void sensors_plus_watchos_start_user_accelerometer(int64_t interval_micros);
SENSORS_PLUS_WATCHOS_EXPORT
int sensors_plus_watchos_read_user_accelerometer(double* out_xyz);
SENSORS_PLUS_WATCHOS_EXPORT
void sensors_plus_watchos_stop_user_accelerometer(void);

SENSORS_PLUS_WATCHOS_EXPORT
void sensors_plus_watchos_start_gyroscope(int64_t interval_micros);
SENSORS_PLUS_WATCHOS_EXPORT
int sensors_plus_watchos_read_gyroscope(double* out_xyz);
SENSORS_PLUS_WATCHOS_EXPORT
void sensors_plus_watchos_stop_gyroscope(void);

SENSORS_PLUS_WATCHOS_EXPORT
void sensors_plus_watchos_start_magnetometer(int64_t interval_micros);
SENSORS_PLUS_WATCHOS_EXPORT
int sensors_plus_watchos_read_magnetometer(double* out_xyz);
SENSORS_PLUS_WATCHOS_EXPORT
void sensors_plus_watchos_stop_magnetometer(void);

#endif  // SENSORS_PLUS_WATCHOS_FFI_H
