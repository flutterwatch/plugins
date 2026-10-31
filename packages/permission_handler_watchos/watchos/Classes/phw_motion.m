// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
//
// Sensors: Motion & Fitness access, through CMMotionActivityManager, asked
// for with a query as the iOS implementation asks. CoreMotion is loaded at
// runtime and only messaged.
//
// Compiled in only when the app's Info.plist sets NSMotionUsageDescription
// (PERMISSION_SENSORS), or by a flutter-watchos that predates `defines`.
// Otherwise sensors answers as PHWUnknownStrategy, and none of this is in
// the app.

#import "phw_internal.h"

#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES) || PERMISSION_SENSORS

#import <CoreMotion/CoreMotion.h>

static PHWStatus _motionStatus(NSInteger status) {
    switch ((CMAuthorizationStatus)status) {
        case CMAuthorizationStatusNotDetermined:
            return PHWStatusDenied;
        case CMAuthorizationStatusRestricted:
            return PHWStatusRestricted;
        case CMAuthorizationStatusDenied:
            return PHWStatusPermanentlyDenied;
        case CMAuthorizationStatusAuthorized:
            return PHWStatusGranted;
    }
    return PHWStatusGranted;
}

@interface PHWMotionStrategy : NSObject <PHWStrategy>
@end

@implementation PHWMotionStrategy {
    // Kept until its query answers.
    CMMotionActivityManager* _manager;
}

- (Class)managerClass {
    return phw_class(@"CoreMotion", @"CMMotionActivityManager");
}

- (void)checkPermission:(PHWPermission)permission done:(PHWStatusHandler)done {
    Class managerClass = [self managerClass];
    done(managerClass == nil
             ? PHWStatusDenied
             : _motionStatus(phw_class_integer(managerClass, @selector(authorizationStatus))));
}

- (void)checkService:(PHWPermission)permission
                done:(PHWServiceHandler)done
              failed:(PHWErrorHandler)failed {
    Class managerClass = [self managerClass];
    BOOL available =
        managerClass != nil && phw_class_bool(managerClass, @selector(isActivityAvailable));
    done(available ? PHWServiceEnabled : PHWServiceDisabled);
}

- (void)requestPermission:(PHWPermission)permission
                     done:(PHWStatusHandler)done
                   failed:(PHWErrorHandler)failed {
    Class managerClass = [self managerClass];
    if (managerClass == nil) {
        done(PHWStatusPermanentlyDenied);
        return;
    }
    PHWStatus status =
        _motionStatus(phw_class_integer(managerClass, @selector(authorizationStatus)));
    if (status != PHWStatusDenied) {
        done(status);
        return;
    }
    if (!phw_has_key(@"NSMotionUsageDescription")) {
        phw_missing_key(@"NSMotionUsageDescription", failed);
        return;
    }
    _manager = [[managerClass alloc] init];
    NSDate* now = [NSDate date];
    [_manager queryActivityStartingFromDate:now
                                     toDate:now
                                    toQueue:[NSOperationQueue mainQueue]
                                withHandler:^(NSArray<CMMotionActivity*>* activities,
                                              NSError* error) {
        self->_manager = nil;
        done(_motionStatus(phw_class_integer(managerClass, @selector(authorizationStatus))));
    }];
}

@end

Class phw_motion_strategy(void) {
    return [PHWMotionStrategy class];
}

#else

Class phw_motion_strategy(void) {
    return [PHWUnknownStrategy class];
}

#endif
