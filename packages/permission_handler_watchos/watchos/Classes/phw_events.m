// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Calendar (full access and write only) and reminders, through
// EKEventStore, answered as the iOS 17 implementation answers them. EventKit
// is loaded at runtime and only messaged.

#import "phw_internal.h"

#import <EventKit/EventKit.h>

static EKEntityType _entityType(PHWPermission permission) {
    return permission == PHWPermissionReminders ? EKEntityTypeReminder : EKEntityTypeEvent;
}

static PHWStatus _eventsStatus(PHWPermission permission, NSInteger status) {
    switch (status) {
        case EKAuthorizationStatusNotDetermined:
            return PHWStatusDenied;
        case EKAuthorizationStatusRestricted:
            return PHWStatusRestricted;
        case EKAuthorizationStatusDenied:
            return PHWStatusPermanentlyDenied;
        case 3:
            // EKAuthorizationStatusFullAccess, which was "authorized".
            return PHWStatusGranted;
        case 4:
            // EKAuthorizationStatusWriteOnly.
            return permission == PHWPermissionCalendarWriteOnly ? PHWStatusGranted
                                                                : PHWStatusDenied;
    }
    return PHWStatusDenied;
}

// The usage description the prompt for `permission` needs.
static NSString* _usageKey(PHWPermission permission) {
    if (@available(watchOS 10.0, *)) {
        switch (permission) {
            case PHWPermissionReminders:
                return @"NSRemindersFullAccessUsageDescription";
            case PHWPermissionCalendarWriteOnly:
                return @"NSCalendarsWriteOnlyAccessUsageDescription";
            default:
                return @"NSCalendarsFullAccessUsageDescription";
        }
    }
    return permission == PHWPermissionReminders ? @"NSRemindersUsageDescription"
                                                : @"NSCalendarsUsageDescription";
}

@implementation PHWEventsStrategy {
    // Kept until its request answers.
    EKEventStore* _store;
}

- (Class)storeClass {
    return phw_class(@"EventKit", @"EKEventStore");
}

- (PHWStatus)statusOf:(Class)storeClass permission:(PHWPermission)permission {
    return _eventsStatus(permission,
                         phw_class_integer_with(storeClass,
                                                @selector(authorizationStatusForEntityType:),
                                                _entityType(permission)));
}

- (void)checkPermission:(PHWPermission)permission done:(PHWStatusHandler)done {
    Class storeClass = [self storeClass];
    done(storeClass == nil ? PHWStatusDenied : [self statusOf:storeClass permission:permission]);
}

- (void)checkService:(PHWPermission)permission
                done:(PHWServiceHandler)done
              failed:(PHWErrorHandler)failed {
    done(PHWServiceNotApplicable);
}

- (void)requestPermission:(PHWPermission)permission
                     done:(PHWStatusHandler)done
                   failed:(PHWErrorHandler)failed {
    Class storeClass = [self storeClass];
    if (storeClass == nil) {
        done(PHWStatusPermanentlyDenied);
        return;
    }
    PHWStatus status = [self statusOf:storeClass permission:permission];
    if (status != PHWStatusDenied) {
        done(status);
        return;
    }
    NSString* key = _usageKey(permission);
    if (!phw_has_key(key)) {
        phw_missing_key(key, failed);
        return;
    }
    _store = [[storeClass alloc] init];
    void (^answer)(BOOL, NSError*) = ^(BOOL granted, NSError* error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_store = nil;
            done(granted ? PHWStatusGranted : PHWStatusPermanentlyDenied);
        });
    };
    if (@available(watchOS 10.0, *)) {
        switch (permission) {
            case PHWPermissionReminders:
                [_store requestFullAccessToRemindersWithCompletion:answer];
                break;
            case PHWPermissionCalendarWriteOnly:
                [_store requestWriteOnlyAccessToEventsWithCompletion:answer];
                break;
            default:
                [_store requestFullAccessToEventsWithCompletion:answer];
                break;
        }
    } else {
        [_store requestAccessToEntityType:_entityType(permission) completion:answer];
    }
}

@end
