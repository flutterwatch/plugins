// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `wakelock_plus`, over dart:ffi.
//
// watchOS has no idle timer an app can turn off. What keeps a watch app
// running and in front with the wrist down is an extended runtime session
// (WKExtendedRuntimeSession), whose type comes from the Info.plist's
// WKBackgroundModes: self-care, mindfulness, physical-therapy or alarm. The
// wakelock is that session: on while it runs, off when it ends.

#ifndef WAKELOCK_PLUS_WATCHOS_FFI_H
#define WAKELOCK_PLUS_WATCHOS_FFI_H

#include <stdint.h>

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it.
#define WAKELOCK_PLUS_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// What `state` reports. Mirrored in lib/wakelock_plus_watchos.dart.
enum {
  kWakelockPlusWatchosOff = 0,
  kWakelockPlusWatchosStarting = 1,
  kWakelockPlusWatchosOn = 2,
};

// 1 when the Info.plist's WKBackgroundModes names a session type, 0 otherwise.
WAKELOCK_PLUS_WATCHOS_EXPORT
int wakelock_plus_watchos_has_session_mode(void);

// Starts a session unless one is starting or running. Must be called while
// the app is active, as watchOS requires.
WAKELOCK_PLUS_WATCHOS_EXPORT
void wakelock_plus_watchos_start(void);

// Ends the session, if any.
WAKELOCK_PLUS_WATCHOS_EXPORT
void wakelock_plus_watchos_stop(void);

// One of the kWakelockPlusWatchos* states.
WAKELOCK_PLUS_WATCHOS_EXPORT
int wakelock_plus_watchos_state(void);

// The WKExtendedRuntimeSessionErrorCode of the last session that ended with
// an error, or 0 when the last one ended without one.
WAKELOCK_PLUS_WATCHOS_EXPORT
int64_t wakelock_plus_watchos_last_error(void);

/// Called when the session starts or ends. Carries no value: Dart re-reads
/// `state`.
typedef void (*wakelock_plus_watchos_cb)(int64_t unused);

/// Registers the function to wake Dart on a change, or NULL to stop.
WAKELOCK_PLUS_WATCHOS_EXPORT
void wakelock_plus_watchos_set_callback(wakelock_plus_watchos_cb callback);

#endif  // WAKELOCK_PLUS_WATCHOS_FFI_H
