// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The wakelock as a WKExtendedRuntimeSession. See the header. The session is
// created, started and ended on the main thread, where WatchKit wants it;
// its state is mirrored under a lock for Dart.
//
// Each start and stop bumps a generation, and a session's callbacks change
// the state only while its own generation is current, so a session that
// reports "started" just after a stop cannot turn the wakelock back on.

#import "wakelock_plus_watchos_ffi.h"

#import <Foundation/Foundation.h>
#import <WatchKit/WatchKit.h>
#import <os/lock.h>

static os_unfair_lock _lock = OS_UNFAIR_LOCK_INIT;
static wakelock_plus_watchos_cb _callback = NULL;
static int _state = kWakelockPlusWatchosOff;
static int64_t _lastError = 0;
static int64_t _generation = 0;

static void _signal(void) {
    os_unfair_lock_lock(&_lock);
    wakelock_plus_watchos_cb callback = _callback;
    os_unfair_lock_unlock(&_lock);
    if (callback != NULL) {
        callback(0);
    }
}

@interface WakelockPlusWatchosDelegate : NSObject <WKExtendedRuntimeSessionDelegate>
// Main thread only.
@property(nonatomic, strong) WKExtendedRuntimeSession* session;
@property(nonatomic, assign) int64_t generation;
@end

@implementation WakelockPlusWatchosDelegate

- (void)extendedRuntimeSessionDidStart:(WKExtendedRuntimeSession*)session {
    if (session != self.session) {
        return;
    }
    os_unfair_lock_lock(&_lock);
    BOOL current = self.generation == _generation;
    if (current) {
        _state = kWakelockPlusWatchosOn;
    }
    os_unfair_lock_unlock(&_lock);
    if (current) {
        _signal();
    }
}

- (void)extendedRuntimeSessionWillExpire:(WKExtendedRuntimeSession*)session {
    // Still running until it is invalidated, which follows.
}

- (void)extendedRuntimeSession:(WKExtendedRuntimeSession*)session
    didInvalidateWithReason:(WKExtendedRuntimeSessionInvalidationReason)reason
                      error:(NSError*)error {
    if (session != self.session) {
        return;
    }
    self.session = nil;
    os_unfair_lock_lock(&_lock);
    BOOL current = self.generation == _generation;
    if (current) {
        _state = kWakelockPlusWatchosOff;
        _lastError = error == nil ? 0 : error.code;
    }
    os_unfair_lock_unlock(&_lock);
    if (current) {
        _signal();
    }
}

@end

static WakelockPlusWatchosDelegate* _delegate(void) {
    static WakelockPlusWatchosDelegate* delegate;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        delegate = [[WakelockPlusWatchosDelegate alloc] init];
    });
    return delegate;
}

void wakelock_plus_watchos_set_callback(wakelock_plus_watchos_cb callback) {
    os_unfair_lock_lock(&_lock);
    _callback = callback;
    os_unfair_lock_unlock(&_lock);
}

int wakelock_plus_watchos_has_session_mode(void) {
    id modes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"WKBackgroundModes"];
    if (![modes isKindOfClass:[NSArray class]]) {
        return 0;
    }
    for (NSString* mode in @[ @"self-care", @"mindfulness", @"physical-therapy", @"alarm" ]) {
        if ([modes containsObject:mode]) {
            return 1;
        }
    }
    return 0;
}

void wakelock_plus_watchos_start(void) {
    os_unfair_lock_lock(&_lock);
    BOOL idle = _state == kWakelockPlusWatchosOff;
    int64_t generation = 0;
    if (idle) {
        _state = kWakelockPlusWatchosStarting;
        _lastError = 0;
        generation = ++_generation;
    }
    os_unfair_lock_unlock(&_lock);
    if (!idle) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        WakelockPlusWatchosDelegate* delegate = _delegate();
        WKExtendedRuntimeSession* session = [WKExtendedRuntimeSession session];
        session.delegate = delegate;
        delegate.session = session;
        delegate.generation = generation;
        [session start];
    });
}

void wakelock_plus_watchos_stop(void) {
    // Off at once, so `state` right after reads what was asked for; the
    // session itself is invalidated on the main thread, after any start
    // queued before this.
    os_unfair_lock_lock(&_lock);
    ++_generation;
    _state = kWakelockPlusWatchosOff;
    os_unfair_lock_unlock(&_lock);
    _signal();
    dispatch_async(dispatch_get_main_queue(), ^{
        WakelockPlusWatchosDelegate* delegate = _delegate();
        WKExtendedRuntimeSession* session = delegate.session;
        delegate.session = nil;
        [session invalidate];
    });
}

int wakelock_plus_watchos_state(void) {
    os_unfair_lock_lock(&_lock);
    int state = _state;
    os_unfair_lock_unlock(&_lock);
    return state;
}

int64_t wakelock_plus_watchos_last_error(void) {
    os_unfair_lock_lock(&_lock);
    int64_t error = _lastError;
    os_unfair_lock_unlock(&_lock);
    return error;
}
