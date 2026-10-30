// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
//
// Calendar (full access and write only) and reminders, through
// EKEventStore, answered as the iOS 17 implementation answers them. EventKit
// is loaded at runtime and only messaged.
//
// Each kind of access is compiled in only when the app's Info.plist sets
// its usage description, as the iOS implementation's macros decide:
// - full access to events (calendar, calendarFullAccess):
//   NSCalendarsFullAccessUsageDescription, PERMISSION_EVENTS_FULL_ACCESS;
// - write-only access to events (calendarWriteOnly):
//   NSCalendarsWriteOnlyAccessUsageDescription, PERMISSION_EVENTS;
// - reminders: NSRemindersFullAccessUsageDescription, PERMISSION_REMINDERS.
// A kind left out answers as PHWUnknownStrategy, and its key and request are
// not in the app; with none of them, none of this is. A flutter-watchos that
// predates `defines` compiles every kind in.

#import "phw_internal.h"

#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES) || PERMISSION_EVENTS_FULL_ACCESS || \
    PERMISSION_EVENTS || PERMISSION_REMINDERS

#import <EventKit/EventKit.h>
#import <objc/message.h>

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

// What asks for one kind of access: the usage description its prompt needs,
// and the EKEventStore request.
typedef struct {
    __unsafe_unretained NSString* key;
    SEL request;
} PHWEventsKind;

// The kind `permission` asks for; its key is nil for a kind this build left
// out.
static PHWEventsKind _kind(PHWPermission permission) {
    switch (permission) {
#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES) || PERMISSION_EVENTS_FULL_ACCESS
        case PHWPermissionCalendar:
        case PHWPermissionCalendarFullAccess:
            return (PHWEventsKind){@"NSCalendarsFullAccessUsageDescription",
                                   @selector(requestFullAccessToEventsWithCompletion:)};
#endif
#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES) || PERMISSION_EVENTS
        case PHWPermissionCalendarWriteOnly:
            return (PHWEventsKind){@"NSCalendarsWriteOnlyAccessUsageDescription",
                                   @selector(requestWriteOnlyAccessToEventsWithCompletion:)};
#endif
#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES) || PERMISSION_REMINDERS
        case PHWPermissionReminders:
            return (PHWEventsKind){@"NSRemindersFullAccessUsageDescription",
                                   @selector(requestFullAccessToRemindersWithCompletion:)};
#endif
        default:
            return (PHWEventsKind){nil, NULL};
    }
}

@interface PHWEventsStrategy : NSObject <PHWStrategy>
@end

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
    // phw_events_strategy() sends only the kinds compiled in here.
    PHWEventsKind kind = _kind(permission);
    if (!phw_has_key(kind.key)) {
        phw_missing_key(kind.key, failed);
        return;
    }
    _store = [[storeClass alloc] init];
    void (^answer)(BOOL, NSError*) = ^(BOOL granted, NSError* error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_store = nil;
            done(granted ? PHWStatusGranted : PHWStatusPermanentlyDenied);
        });
    };
    ((void (*)(id, SEL, void (^)(BOOL, NSError*)))objc_msgSend)(_store, kind.request, answer);
}

@end

Class phw_events_strategy(PHWPermission permission) {
    return _kind(permission).key != nil ? [PHWEventsStrategy class] : [PHWUnknownStrategy class];
}

#else

Class phw_events_strategy(PHWPermission permission) {
    return [PHWUnknownStrategy class];
}

#endif
