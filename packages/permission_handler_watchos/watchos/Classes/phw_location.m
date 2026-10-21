// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Location, when in use and always, through a CLLocationManager the
// strategy keeps, answered as the iOS implementation answers them.
//
// CoreLocation is loaded at runtime and only messaged: no class of it is
// referenced by symbol, so an app that never asks for location links none
// of it.

#import "phw_internal.h"

#import <CoreLocation/CoreLocation.h>
#import <WatchKit/WatchKit.h>

// Set once "always" was asked for: watchOS shows that prompt once, and a
// second request must answer without waiting for a prompt that never comes.
static NSString* const kAskedAlwaysKey = @"dev.flutterwatch.permission_handler.askedAlways";

static PHWStatus _locationStatus(PHWPermission permission, CLAuthorizationStatus status) {
    switch (status) {
        case kCLAuthorizationStatusNotDetermined:
            return PHWStatusDenied;
        case kCLAuthorizationStatusRestricted:
            return PHWStatusRestricted;
        case kCLAuthorizationStatusDenied:
            return PHWStatusPermanentlyDenied;
        case kCLAuthorizationStatusAuthorizedWhenInUse:
            return permission == PHWPermissionLocationAlways ? PHWStatusPermanentlyDenied
                                                             : PHWStatusGranted;
        case kCLAuthorizationStatusAuthorizedAlways:
            return PHWStatusGranted;
    }
    return PHWStatusDenied;
}

@interface PHWLocationStrategy () <CLLocationManagerDelegate>
@end

@implementation PHWLocationStrategy {
    CLLocationManager* _manager;
    // Requests waiting for the wearer's answer, and what they asked for.
    NSMutableArray<PHWStatusHandler>* _waiting;
    PHWPermission _asked;
    id _activeObserver;
}

- (CLLocationManager*)manager {
    if (_manager == nil) {
        Class managerClass = phw_class(@"CoreLocation", @"CLLocationManager");
        _manager = [[managerClass alloc] init];
        _manager.delegate = self;
        _waiting = [NSMutableArray array];
    }
    return _manager;
}

- (void)checkPermission:(PHWPermission)permission done:(PHWStatusHandler)done {
    CLLocationManager* manager = [self manager];
    done(manager == nil ? PHWStatusDenied
                        : _locationStatus(permission, manager.authorizationStatus));
}

- (void)checkService:(PHWPermission)permission
                done:(PHWServiceHandler)done
              failed:(PHWErrorHandler)failed {
    Class managerClass = phw_class(@"CoreLocation", @"CLLocationManager");
    if (managerClass == nil) {
        done(PHWServiceDisabled);
        return;
    }
    // CoreLocation warns that this blocks; it is read off the main queue.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL enabled = phw_class_bool(managerClass, @selector(locationServicesEnabled));
        done(enabled ? PHWServiceEnabled : PHWServiceDisabled);
    });
}

- (void)requestPermission:(PHWPermission)permission
                     done:(PHWStatusHandler)done
                   failed:(PHWErrorHandler)failed {
    CLLocationManager* manager = [self manager];
    if (manager == nil) {
        done(PHWStatusPermanentlyDenied);
        return;
    }
    CLAuthorizationStatus status = manager.authorizationStatus;
    if (permission == PHWPermissionLocationAlways) {
        [self requestAlways:status done:done failed:failed];
        return;
    }
    if (status != kCLAuthorizationStatusNotDetermined) {
        done(_locationStatus(permission, status));
        return;
    }
    if (!phw_has_key(@"NSLocationWhenInUseUsageDescription")) {
        phw_missing_key(@"NSLocationWhenInUseUsageDescription", failed);
        return;
    }
    _asked = permission;
    [_waiting addObject:done];
    [manager requestWhenInUseAuthorization];
}

- (void)requestAlways:(CLAuthorizationStatus)status
                 done:(PHWStatusHandler)done
               failed:(PHWErrorHandler)failed {
    if (!phw_has_key(@"NSLocationAlwaysAndWhenInUseUsageDescription") &&
        !phw_has_key(@"NSLocationAlwaysUsageDescription")) {
        phw_missing_key(@"NSLocationAlwaysAndWhenInUseUsageDescription", failed);
        return;
    }
    if (status == kCLAuthorizationStatusNotDetermined) {
        failed(@"MISSING_WHENINUSE_PERMISSION",
               @"Must have \"When in use\" permission before it is allowed to request "
               @"\"Always\" permission.");
        return;
    }
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if (status != kCLAuthorizationStatusAuthorizedWhenInUse ||
        [defaults boolForKey:kAskedAlwaysKey]) {
        done(_locationStatus(PHWPermissionLocationAlways, status));
        return;
    }
    [defaults setBool:YES forKey:kAskedAlwaysKey];
    _asked = PHWPermissionLocationAlways;
    [_waiting addObject:done];
    // Keeping "while using" changes nothing, so no delegate call comes; the
    // app becoming active again after the prompt is the answer then.
    if (_activeObserver == nil) {
        __weak PHWLocationStrategy* weakSelf = self;
        _activeObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:WKApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* note) {
            PHWLocationStrategy* strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf answer:strongSelf->_manager.authorizationStatus];
            }
        }];
    }
    [_manager requestAlwaysAuthorization];
}

- (void)answer:(CLAuthorizationStatus)status {
    if (_waiting.count == 0) {
        return;
    }
    if (_activeObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:_activeObserver];
        _activeObserver = nil;
    }
    NSArray<PHWStatusHandler>* waiting = [_waiting copy];
    [_waiting removeAllObjects];
    for (PHWStatusHandler done in waiting) {
        done(_locationStatus(_asked, status));
    }
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager*)manager {
    CLAuthorizationStatus status = manager.authorizationStatus;
    // The manager reports its status once on creation, before any answer;
    // and "always" still at "when in use" is no answer yet either.
    if (status == kCLAuthorizationStatusNotDetermined ||
        (_asked == PHWPermissionLocationAlways &&
         status == kCLAuthorizationStatusAuthorizedWhenInUse)) {
        return;
    }
    [self answer:status];
}

@end
