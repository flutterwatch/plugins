// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// CoreLocation-backed geolocation for watchOS. A shared CLLocationManager with
// a delegate caches the most recent fix and wakes Dart; the FFI
// `read_position` copies it out. Accuracy indices and the Position field order
// match geolocator.

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
static int64_t _accuracyRequestsDone = 0;

void geolocator_watchos_set_callback(geolocator_watchos_cb callback) {
    os_unfair_lock_lock(&_lock);
    _callback = callback;
    os_unfair_lock_unlock(&_lock);
}

// Wakes Dart. The callback pointer is read under the lock but invoked outside
// it, because Dart may call straight back into this file.
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

// Whether the Info.plist allows background location updates. CoreLocation
// treats allowsBackgroundLocationUpdates = YES without it as a fatal error.
static BOOL _hasBackgroundLocationMode(void) {
    for (NSString* key in @[ @"UIBackgroundModes", @"WKBackgroundModes" ]) {
        id modes = [[NSBundle mainBundle] objectForInfoDictionaryKey:key];
        if ([modes isKindOfClass:[NSArray class]] &&
            [modes containsObject:@"location"]) {
            return YES;
        }
    }
    return NO;
}

static CLActivityType _activityTypeFor(int raw) {
    if (raw == 6) {
        if (@available(watchOS 27.0, *)) {
            return CLActivityTypeMaritime;
        }
        return CLActivityTypeOther;
    }
    return raw >= CLActivityTypeOther && raw <= CLActivityTypeAirborne
               ? (CLActivityType)raw
               : CLActivityTypeOther;
}

void geolocator_watchos_start_updates(int accuracy, double distance_filter,
                                      int activity_type, int allow_background) {
    CLLocationManager* m = _manager();
    BOOL background = allow_background != 0 && _hasBackgroundLocationMode();
    dispatch_async(dispatch_get_main_queue(), ^{
        m.desiredAccuracy = _accuracyFor(accuracy);
        m.distanceFilter =
            distance_filter > 0 ? distance_filter : kCLDistanceFilterNone;
        if (activity_type != 0) {
            m.activityType = _activityTypeFor(activity_type);
        }
        m.allowsBackgroundLocationUpdates = background;
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

int geolocator_watchos_accuracy_authorization(void) {
    return _manager().accuracyAuthorization == CLAccuracyAuthorizationFullAccuracy
               ? 1
               : 0;
}

int geolocator_watchos_request_temporary_full_accuracy(const char* purpose_key) {
    if ([[NSBundle mainBundle] objectForInfoDictionaryKey:
                                   @"NSLocationTemporaryUsageDescriptionDictionary"] == nil) {
        return 0;
    }
    // Copied now: Dart releases the string as soon as this returns.
    NSString* key = purpose_key == NULL ? @"" : [NSString stringWithUTF8String:purpose_key];
    CLLocationManager* m = _manager();
    dispatch_async(dispatch_get_main_queue(), ^{
        [m requestTemporaryFullAccuracyAuthorizationWithPurposeKey:key
                                                        completion:^(NSError* error) {
            os_unfair_lock_lock(&_lock);
            _accuracyRequestsDone++;
            os_unfair_lock_unlock(&_lock);
            _signal();
        }];
    });
    return 1;
}

int64_t geolocator_watchos_accuracy_requests_done(void) {
    os_unfair_lock_lock(&_lock);
    int64_t done = _accuracyRequestsDone;
    os_unfair_lock_unlock(&_lock);
    return done;
}
