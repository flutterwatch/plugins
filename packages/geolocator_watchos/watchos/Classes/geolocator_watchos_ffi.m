// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// CoreLocation-backed geolocation for watchOS. A shared CLLocationManager with
// a delegate caches the most recent fix; the FFI `read_position` copies it out
// for the Dart poller. Accuracy indices and the Position field order match
// geolocator.

#import "geolocator_watchos_ffi.h"

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>
#import <os/lock.h>

typedef struct {
    double latitude, longitude, accuracy, altitude, altitudeAccuracy;
    double heading, headingAccuracy, speed, speedAccuracy, timestampMillis;
    int has;
} Fix;

static os_unfair_lock _lock = OS_UNFAIR_LOCK_INIT;
static Fix _fix;
static geolocator_watchos_cb _callback = NULL;

void geolocator_watchos_set_callback(geolocator_watchos_cb callback) {
    os_unfair_lock_lock(&_lock);
    _callback = callback;
    os_unfair_lock_unlock(&_lock);
}

// Wakes Dart. The callback pointer is read under the lock but invoked outside
// it, because Dart is free to call straight back into this file.
static void _signal(void) {
    os_unfair_lock_lock(&_lock);
    geolocator_watchos_cb callback = _callback;
    os_unfair_lock_unlock(&_lock);
    if (callback != NULL) {
        callback(0);
    }
}

@interface GeolocatorWatchosDelegate : NSObject <CLLocationManagerDelegate>
@end

@implementation GeolocatorWatchosDelegate

- (void)locationManager:(CLLocationManager*)manager
     didUpdateLocations:(NSArray<CLLocation*>*)locations {
    CLLocation* location = locations.lastObject;
    if (location == nil) {
        return;
    }
    os_unfair_lock_lock(&_lock);
    _fix.latitude = location.coordinate.latitude;
    _fix.longitude = location.coordinate.longitude;
    _fix.accuracy = location.horizontalAccuracy;
    _fix.altitude = location.altitude;
    _fix.altitudeAccuracy = location.verticalAccuracy;
    _fix.heading = location.course;
    _fix.headingAccuracy = location.courseAccuracy;
    _fix.speed = location.speed;
    _fix.speedAccuracy = location.speedAccuracy;
    _fix.timestampMillis = location.timestamp.timeIntervalSince1970 * 1000.0;
    _fix.has = 1;
    os_unfair_lock_unlock(&_lock);
    _signal();
}

- (void)locationManager:(CLLocationManager*)manager
       didFailWithError:(NSError*)error {
    // Leave the last cached fix in place; the caller's deadline decides.
    // Still wake Dart: a waiter should re-check rather than sit until timeout.
    _signal();
}

// Authorization changes are the other thing Dart waits on — the answer to the
// system permission prompt arrives here, not on any value it could poll.
- (void)locationManagerDidChangeAuthorization:(CLLocationManager*)manager {
    _signal();
}

@end

static CLLocationManager* _manager(void) {
    static CLLocationManager* manager;
    static GeolocatorWatchosDelegate* delegate;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // CLLocationManager must be created on a thread with a run loop; the
        // main queue is guaranteed to have one.
        dispatch_sync(dispatch_get_main_queue(), ^{
            delegate = [[GeolocatorWatchosDelegate alloc] init];
            manager = [[CLLocationManager alloc] init];
            manager.delegate = delegate;
        });
    });
    return manager;
}

static CLLocationAccuracy _accuracyFor(int index) {
    switch (index) {
        case 0:
            return kCLLocationAccuracyThreeKilometers;
        case 1:
            return kCLLocationAccuracyKilometer;
        case 2:
            return kCLLocationAccuracyHundredMeters;
        case 3:
            return kCLLocationAccuracyNearestTenMeters;
        case 5:
            return kCLLocationAccuracyBestForNavigation;
        case 6:
            return kCLLocationAccuracyReduced;
        case 4:
        default:
            return kCLLocationAccuracyBest;
    }
}

int geolocator_watchos_is_service_enabled(void) {
    return [CLLocationManager locationServicesEnabled] ? 1 : 0;
}

int geolocator_watchos_check_permission(void) {
    return (int)_manager().authorizationStatus;
}

void geolocator_watchos_request_permission(void) {
    CLLocationManager* m = _manager();
    dispatch_async(dispatch_get_main_queue(), ^{
        [m requestWhenInUseAuthorization];
    });
}

void geolocator_watchos_start_updates(int accuracy, double distance_filter) {
    CLLocationManager* m = _manager();
    dispatch_async(dispatch_get_main_queue(), ^{
        m.desiredAccuracy = _accuracyFor(accuracy);
        m.distanceFilter =
            distance_filter > 0 ? distance_filter : kCLDistanceFilterNone;
        [m startUpdatingLocation];
    });
}

void geolocator_watchos_request_location(void) {
    CLLocationManager* m = _manager();
    dispatch_async(dispatch_get_main_queue(), ^{
        [m requestLocation];
    });
}

int geolocator_watchos_read_position(double* out) {
    os_unfair_lock_lock(&_lock);
    int has = _fix.has;
    if (has) {
        out[0] = _fix.latitude;
        out[1] = _fix.longitude;
        out[2] = _fix.accuracy;
        out[3] = _fix.altitude;
        out[4] = _fix.altitudeAccuracy;
        out[5] = _fix.heading;
        out[6] = _fix.headingAccuracy;
        out[7] = _fix.speed;
        out[8] = _fix.speedAccuracy;
        out[9] = _fix.timestampMillis;
    }
    os_unfair_lock_unlock(&_lock);
    return has;
}

void geolocator_watchos_stop_updates(void) {
    CLLocationManager* m = _manager();
    dispatch_async(dispatch_get_main_queue(), ^{
        [m stopUpdatingLocation];
    });
}
