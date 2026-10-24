// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
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

// How long after the app becomes active a status still "not determined"
// waits for the delegate before it counts as a prompt closed unanswered.
static const NSTimeInterval kUnansweredDelay = 1.0;

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
    id _resignObserver;
    // Whether the app resigned active since the request: the prompt taking
    // the screen does that, and only a return after it is an answer.
    BOOL _resigned;
    // Goes up with every answer, so a re-read armed before one stands down.
    NSUInteger _answers;
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
    // A prompt closed without an answer (the crown pressed) sends no
    // delegate call on watchOS, not even the second "not determined" the
    // iOS implementation waits for (seen on the watchOS 27.0 Simulator), so
    // the app becoming active again is the answer then.
    [self observeActive];
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
    [self observeActive];
    [_manager requestAlwaysAuthorization];
}

// Answers the waiting requests when the app becomes active again after the
// prompt took the screen (it resigned active first), with what the status is
// then. An answer the wearer gave reaches the delegate too, maybe just after:
// a status still "not determined" is read again a moment later before it
// counts as a prompt closed unanswered, unless the delegate answered in
// between.
- (void)observeActive {
    if (_activeObserver != nil) {
        return;
    }
    _resigned = NO;
    __weak PHWLocationStrategy* weakSelf = self;
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    _resignObserver = [center addObserverForName:WKApplicationWillResignActiveNotification
                                          object:nil
                                           queue:[NSOperationQueue mainQueue]
                                      usingBlock:^(NSNotification* note) {
        PHWLocationStrategy* strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf->_resigned = YES;
        }
    }];
    _activeObserver = [center addObserverForName:WKApplicationDidBecomeActiveNotification
                                          object:nil
                                           queue:[NSOperationQueue mainQueue]
                                      usingBlock:^(NSNotification* note) {
        PHWLocationStrategy* strongSelf = weakSelf;
        if (strongSelf == nil || !strongSelf->_resigned) {
            return;
        }
        if (strongSelf->_manager.authorizationStatus != kCLAuthorizationStatusNotDetermined) {
            [strongSelf answer:strongSelf->_manager.authorizationStatus];
            return;
        }
        NSUInteger answers = strongSelf->_answers;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kUnansweredDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            PHWLocationStrategy* later = weakSelf;
            // An answer since, from the delegate, stands this re-read down:
            // a request made after it is not answered by it.
            if (later != nil && later->_answers == answers) {
                [later answer:later->_manager.authorizationStatus];
            }
        });
    }];
}

- (void)answer:(CLAuthorizationStatus)status {
    if (_waiting.count == 0) {
        return;
    }
    _answers++;
    if (_activeObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:_activeObserver];
        _activeObserver = nil;
    }
    if (_resignObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:_resignObserver];
        _resignObserver = nil;
    }
    NSArray<PHWStatusHandler>* waiting = [_waiting copy];
    [_waiting removeAllObjects];
    for (PHWStatusHandler done in waiting) {
        done(_locationStatus(_asked, status));
    }
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager*)manager {
    CLAuthorizationStatus status = manager.authorizationStatus;
    // The manager reports its status once on creation, before any answer, and
    // a prompt closed unanswered is caught by observeActive; "always" still
    // at "when in use" is no answer yet either.
    if (status == kCLAuthorizationStatusNotDetermined ||
        (_asked == PHWPermissionLocationAlways &&
         status == kCLAuthorizationStatusAuthorizedWhenInUse)) {
        return;
    }
    [self answer:status];
}

@end
