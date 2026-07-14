// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// CoreMotion-backed sensors for watchOS. A single shared CMMotionManager
// delivers updates onto a background queue; each handler caches the latest
// x/y/z triple under a lock, and the FFI `read_*` copies it out for the Dart
// poller. Unit conventions match the sensors_plus iOS implementation
// (accelerations in m/s^2 with the axis sign flipped; gyroscope in rad/s;
// magnetometer in microtesla).

#import "sensors_plus_watchos_ffi.h"

#import <CoreMotion/CoreMotion.h>
#import <Foundation/Foundation.h>
#import <os/lock.h>

// Matches sensors_plus: CMAcceleration is in g, reported as m/s^2.
static const double kGravity = 9.81;

// One cached sample. `has` is set once the first update lands.
typedef struct {
    double x, y, z;
    int has;
} Sample;

static CMMotionManager* _manager(void) {
    static CMMotionManager* manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        manager = [[CMMotionManager alloc] init];
    });
    return manager;
}

static NSOperationQueue* _queue(void) {
    static NSOperationQueue* queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = [[NSOperationQueue alloc] init];
        queue.name = @"dev.flutterwatch.sensors_plus_watchos";
    });
    return queue;
}

static os_unfair_lock _lock = OS_UNFAIR_LOCK_INIT;
static Sample _accel, _userAccel, _gyro, _mag;

static void _store(Sample* slot, double x, double y, double z) {
    os_unfair_lock_lock(&_lock);
    slot->x = x;
    slot->y = y;
    slot->z = z;
    slot->has = 1;
    os_unfair_lock_unlock(&_lock);
}

static int _load(Sample* slot, double* out_xyz) {
    os_unfair_lock_lock(&_lock);
    int has = slot->has;
    if (has) {
        out_xyz[0] = slot->x;
        out_xyz[1] = slot->y;
        out_xyz[2] = slot->z;
    }
    os_unfair_lock_unlock(&_lock);
    return has;
}

static NSTimeInterval _interval(int64_t micros) {
    return micros > 0 ? (double)micros / 1000000.0 : 0.2;
}

// ---- Accelerometer (raw) ----------------------------------------------------

void sensors_plus_watchos_start_accelerometer(int64_t interval_micros) {
    CMMotionManager* m = _manager();
    if (!m.accelerometerAvailable) {
        return;
    }
    m.accelerometerUpdateInterval = _interval(interval_micros);
    [m startAccelerometerUpdatesToQueue:_queue()
                            withHandler:^(CMAccelerometerData* data,
                                          NSError* error) {
        if (data == nil || error != nil) {
            return;
        }
        CMAcceleration a = data.acceleration;
        _store(&_accel, -a.x * kGravity, -a.y * kGravity, -a.z * kGravity);
    }];
}

int sensors_plus_watchos_read_accelerometer(double* out_xyz) {
    return _load(&_accel, out_xyz);
}

void sensors_plus_watchos_stop_accelerometer(void) {
    [_manager() stopAccelerometerUpdates];
}

// ---- User accelerometer (gravity removed, via device motion) ----------------

void sensors_plus_watchos_start_user_accelerometer(int64_t interval_micros) {
    CMMotionManager* m = _manager();
    if (!m.deviceMotionAvailable) {
        return;
    }
    m.deviceMotionUpdateInterval = _interval(interval_micros);
    [m startDeviceMotionUpdatesToQueue:_queue()
                           withHandler:^(CMDeviceMotion* data, NSError* error) {
        if (data == nil || error != nil) {
            return;
        }
        CMAcceleration a = data.userAcceleration;
        _store(&_userAccel, -a.x * kGravity, -a.y * kGravity, -a.z * kGravity);
    }];
}

int sensors_plus_watchos_read_user_accelerometer(double* out_xyz) {
    return _load(&_userAccel, out_xyz);
}

void sensors_plus_watchos_stop_user_accelerometer(void) {
    [_manager() stopDeviceMotionUpdates];
}

// ---- Gyroscope --------------------------------------------------------------

void sensors_plus_watchos_start_gyroscope(int64_t interval_micros) {
    CMMotionManager* m = _manager();
    if (!m.gyroAvailable) {
        return;
    }
    m.gyroUpdateInterval = _interval(interval_micros);
    [m startGyroUpdatesToQueue:_queue()
                   withHandler:^(CMGyroData* data, NSError* error) {
        if (data == nil || error != nil) {
            return;
        }
        CMRotationRate r = data.rotationRate;
        _store(&_gyro, r.x, r.y, r.z);
    }];
}

int sensors_plus_watchos_read_gyroscope(double* out_xyz) {
    return _load(&_gyro, out_xyz);
}

void sensors_plus_watchos_stop_gyroscope(void) {
    [_manager() stopGyroUpdates];
}

// ---- Magnetometer -----------------------------------------------------------

void sensors_plus_watchos_start_magnetometer(int64_t interval_micros) {
    CMMotionManager* m = _manager();
    if (!m.magnetometerAvailable) {
        return;
    }
    m.magnetometerUpdateInterval = _interval(interval_micros);
    [m startMagnetometerUpdatesToQueue:_queue()
                           withHandler:^(CMMagnetometerData* data,
                                         NSError* error) {
        if (data == nil || error != nil) {
            return;
        }
        CMMagneticField f = data.magneticField;
        _store(&_mag, f.x, f.y, f.z);
    }];
}

int sensors_plus_watchos_read_magnetometer(double* out_xyz) {
    return _load(&_mag, out_xyz);
}

void sensors_plus_watchos_stop_magnetometer(void) {
    [_manager() stopMagnetometerUpdates];
}
