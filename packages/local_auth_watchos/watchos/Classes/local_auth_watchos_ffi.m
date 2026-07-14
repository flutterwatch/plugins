// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// LocalAuthentication-backed auth for watchOS. The watch supports only
// device-owner authentication (passcode / wrist unlock); there is no biometry,
// so biometrics-only policies fail. evaluatePolicy is asynchronous, so the
// result is cached under a lock and polled by the Dart side.

#import "local_auth_watchos_ffi.h"

#import <Foundation/Foundation.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <os/lock.h>

// Poll states shared with Dart.
enum { kPending = 0, kSuccess = 1, kFailure = 2 };

static os_unfair_lock _lock = OS_UNFAIR_LOCK_INIT;
static int _state = kFailure;
// The context is retained for the lifetime of an evaluation so its completion
// handler is delivered.
static LAContext* _context;

static void _setState(int state) {
    os_unfair_lock_lock(&_lock);
    _state = state;
    os_unfair_lock_unlock(&_lock);
}

int local_auth_watchos_is_device_supported(void) {
    if (@available(watchOS 9.0, *)) {
        LAContext* ctx = [[LAContext alloc] init];
        BOOL ok = [ctx canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication
                                   error:nil];
        return ok ? 1 : 0;
    }
    return 0;
}

int local_auth_watchos_supports_biometrics(void) {
    // watchOS has no Face ID / Touch ID.
    return 0;
}

void local_auth_watchos_authenticate(const char* reason, int biometric_only) {
    @autoreleasepool {
        _setState(kPending);
        // watchOS has no biometry, so a biometrics-only request cannot be
        // satisfied. (The biometrics policy constant does not even exist on
        // watchOS, so it must not be referenced.)
        if (biometric_only) {
            _setState(kFailure);
            return;
        }
        if (@available(watchOS 9.0, *)) {
            NSString* localizedReason = reason != NULL
                ? [NSString stringWithUTF8String:reason]
                : @"Authenticate";
            const LAPolicy policy = LAPolicyDeviceOwnerAuthentication;

            LAContext* ctx = [[LAContext alloc] init];
            _context = ctx;  // retain across the async callback

            NSError* canError = nil;
            if (![ctx canEvaluatePolicy:policy error:&canError]) {
                // No passcode set.
                _setState(kFailure);
                return;
            }
            [ctx evaluatePolicy:policy
                localizedReason:localizedReason
                          reply:^(BOOL success, NSError* error) {
                _setState(success ? kSuccess : kFailure);
            }];
        } else {
            _setState(kFailure);
        }
    }
}

int local_auth_watchos_poll(void) {
    os_unfair_lock_lock(&_lock);
    int state = _state;
    os_unfair_lock_unlock(&_lock);
    return state;
}

int local_auth_watchos_stop(void) {
    if (@available(watchOS 9.0, *)) {
        [_context invalidate];
    }
    _setState(kFailure);
    return 1;
}
