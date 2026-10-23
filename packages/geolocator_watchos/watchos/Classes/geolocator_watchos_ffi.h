// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `geolocator`, over dart:ffi.
//
// Backed by CoreLocation, which is available on watchOS. As in
// geolocator_apple, two CLLocationManagers share one delegate: one runs the
// position stream with its settings, the other answers single position
// requests. The delegate caches the latest fix, counts the fixes it accepts,
// and wakes Dart through the callback below; Dart reads the fix back with
// `read_position`. Permission requests and authorization status map to
// geolocator's LocationPermission.

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

// Begins the stream's continuous updates. `accuracy` is a geolocator
// LocationAccuracy index (0 lowest … 4 best, 5 bestForNavigation, 6 reduced);
// `distance_filter` is in metres (<= 0 means none). `activity_type` is a
// CLActivityType raw value, or 6 for maritime; any other value, 0 included,
// means CLActivityTypeOther. A nonzero `allow_background` turns on
// allowsBackgroundLocationUpdates, but only when the Info.plist's
// UIBackgroundModes has "location": CoreLocation asserts otherwise, and does
// so even when WKBackgroundModes has it.
GEOLOCATOR_WATCHOS_EXPORT
void geolocator_watchos_start_updates(int accuracy, double distance_filter,
                                      int activity_type, int allow_background);

// Starts the single-request manager at `accuracy` (as above), with no
// distance filter. It skips cached fixes more than 5 seconds old and stops
// itself after the first fix it accepts.
GEOLOCATOR_WATCHOS_EXPORT
void geolocator_watchos_request_location(int accuracy);

// Stops the single-request manager, for a request that gave up.
GEOLOCATOR_WATCHOS_EXPORT
void geolocator_watchos_stop_location_request(void);

// Fills out[0..9] with latitude, longitude, accuracy, altitude,
// altitudeAccuracy, heading, headingAccuracy, speed, speedAccuracy, and the
// timestamp in milliseconds since the epoch. Returns 1 if a fix is cached.
GEOLOCATOR_WATCHOS_EXPORT
int geolocator_watchos_read_position(double* out);

// How many fixes either manager has delivered: it goes up with each one, so
// Dart can tell a new fix from the cached one, even at the same place.
GEOLOCATOR_WATCHOS_EXPORT
int64_t geolocator_watchos_position_count(void);

// Stops the stream's continuous updates.
GEOLOCATOR_WATCHOS_EXPORT
void geolocator_watchos_stop_updates(void);

// The accuracy the wearer allows, as a geolocator LocationAccuracyStatus
// index: 0 reduced, 1 precise.
GEOLOCATOR_WATCHOS_EXPORT
int geolocator_watchos_accuracy_authorization(void);

// Asks for full accuracy for this session, explained by `purpose_key`, a key
// of the Info.plist's NSLocationTemporaryUsageDescriptionDictionary. Returns 0
// without asking when the Info.plist has no such dictionary, 1 otherwise; the
// answer is read with `accuracy_authorization` once `accuracy_requests_done`
// has gone up.
GEOLOCATOR_WATCHOS_EXPORT
int geolocator_watchos_request_temporary_full_accuracy(const char* purpose_key);

// How many temporary full-accuracy requests have finished.
GEOLOCATOR_WATCHOS_EXPORT
int64_t geolocator_watchos_accuracy_requests_done(void);

// What a signal reports, so Dart re-reads only what changed.
#define GEOLOCATOR_WATCHOS_SIGNAL_POSITION 0       // a fix, or a failed update
#define GEOLOCATOR_WATCHOS_SIGNAL_AUTHORIZATION 1  // authorization or service
#define GEOLOCATOR_WATCHOS_SIGNAL_ACCURACY 2       // an accuracy request ended

/// Called from the CLLocationManager delegate when a new fix lands, the
/// authorization or accuracy changes, or a temporary accuracy request ends.
///
/// Carries one of the kinds above and no value: the Dart end is a
/// `NativeCallable.listener` and runs asynchronously, so it re-reads what it
/// waits on rather than trusting a pointer captured at signal time.
typedef void (*geolocator_watchos_cb)(int64_t kind);

/// Registers the function to wake Dart on a new fix, or NULL to stop.
GEOLOCATOR_WATCHOS_EXPORT
void geolocator_watchos_set_callback(geolocator_watchos_cb callback);

#endif  // GEOLOCATOR_WATCHOS_FFI_H
