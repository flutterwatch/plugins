// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `geolocator`, over dart:ffi.
//
// Backed by CoreLocation (CLLocationManager), which is available on watchOS.
// Location updates arrive asynchronously on a delegate, which caches the
// latest fix; the Dart side polls `read_position`. Permission requests and
// authorization status map to geolocator's LocationPermission.

#ifndef GEOLOCATOR_WATCHOS_FFI_H
#define GEOLOCATOR_WATCHOS_FFI_H

// For int64_t in the callback typedef below.
#include <stdint.h>

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it.
#define GEOLOCATOR_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// 1 if system location services are enabled, 0 otherwise.
GEOLOCATOR_WATCHOS_EXPORT
int geolocator_watchos_is_service_enabled(void);

// Raw CLAuthorizationStatus: 0 notDetermined, 1 restricted, 2 denied,
// 3 authorizedAlways, 4 authorizedWhenInUse.
GEOLOCATOR_WATCHOS_EXPORT
int geolocator_watchos_check_permission(void);

// Requests when-in-use authorization (asynchronous; poll check_permission).
GEOLOCATOR_WATCHOS_EXPORT
void geolocator_watchos_request_permission(void);

// Begins continuous updates. `accuracy` is a geolocator LocationAccuracy index
// (0 lowest … 4 best, 5 bestForNavigation, 6 reduced); `distance_filter` is in
// metres (<= 0 means none).
GEOLOCATOR_WATCHOS_EXPORT
void geolocator_watchos_start_updates(int accuracy, double distance_filter);

// Requests a single location fix.
GEOLOCATOR_WATCHOS_EXPORT
void geolocator_watchos_request_location(void);

// Fills out[0..9] with latitude, longitude, accuracy, altitude,
// altitudeAccuracy, heading, headingAccuracy, speed, speedAccuracy, and the
// timestamp in milliseconds since the epoch. Returns 1 if a fix is cached.
GEOLOCATOR_WATCHOS_EXPORT
int geolocator_watchos_read_position(double* out);

// Stops continuous updates.
GEOLOCATOR_WATCHOS_EXPORT
void geolocator_watchos_stop_updates(void);

/// Called from the CLLocationManager delegate when a new fix lands.
///
/// Carries no value: the Dart end is a `NativeCallable.listener` and runs
/// asynchronously, so it re-reads `..._read_position` rather than trusting a
/// pointer captured at signal time.
typedef void (*geolocator_watchos_cb)(int64_t unused);

/// Registers the function to wake Dart on a new fix, or NULL to stop.
GEOLOCATOR_WATCHOS_EXPORT
void geolocator_watchos_set_callback(geolocator_watchos_cb callback);

#endif  // GEOLOCATOR_WATCHOS_FFI_H
