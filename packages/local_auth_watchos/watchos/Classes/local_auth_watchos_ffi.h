// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `local_auth`, over dart:ffi.
//
// Backed by LocalAuthentication (LAContext), available on watchOS 9+. The
// watch has no Face ID / Touch ID, so only device-owner (passcode / wrist
// unlock) authentication is offered — biometric-only requests fail.
//
// `evaluatePolicy` is asynchronous, so `authenticate` kicks it off and stores
// the pending/success/failure state, which the Dart side polls via `poll`.

#ifndef LOCAL_AUTH_WATCHOS_FFI_H
#define LOCAL_AUTH_WATCHOS_FFI_H

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it.
#define LOCAL_AUTH_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// 1 if the device can evaluate device-owner authentication (a passcode is set),
// 0 otherwise. Maps to isDeviceSupported().
LOCAL_AUTH_WATCHOS_EXPORT
int local_auth_watchos_is_device_supported(void);

// 1 if biometric authentication is available. Always 0 on watchOS (no
// Face ID / Touch ID). Maps to deviceSupportsBiometrics().
LOCAL_AUTH_WATCHOS_EXPORT
int local_auth_watchos_supports_biometrics(void);

// Starts an asynchronous evaluation, resetting the poll state to pending.
// `biometric_only` selects the biometrics-only policy (which fails on watchOS).
LOCAL_AUTH_WATCHOS_EXPORT
void local_auth_watchos_authenticate(const char* reason, int biometric_only);

// Poll state: 0 = pending, 1 = success, 2 = failure.
LOCAL_AUTH_WATCHOS_EXPORT
int local_auth_watchos_poll(void);

// Cancels any in-progress evaluation. Returns 1.
LOCAL_AUTH_WATCHOS_EXPORT
int local_auth_watchos_stop(void);

#endif  // LOCAL_AUTH_WATCHOS_FFI_H
