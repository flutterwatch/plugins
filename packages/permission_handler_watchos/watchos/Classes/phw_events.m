// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
//
// Calendar (full access and write only) and reminders, through
// EKEventStore, answered as the iOS 17 implementation answers them. EventKit
// is loaded at runtime and only messaged.
//
// The macros decide as the iOS implementation's do. Any of the three below
// compiles this strategy in, or a flutter-watchos that predates `defines`
// does. All four permissions then read their status from EventKit, and the
// service is not applicable. Each macro adds the prompts its key allows:
// - PERMISSION_EVENTS_FULL_ACCESS (NSCalendarsFullAccessUsageDescription):
//   calendar and calendarFullAccess, and calendarWriteOnly too;
// - PERMISSION_EVENTS (NSCalendarsWriteOnlyAccessUsageDescription):
//   calendarWriteOnly;
// - PERMISSION_REMINDERS (NSRemindersFullAccessUsageDescription): reminders.
// A request whose prompt is left out answers its status and asks nothing;
// that prompt's key and request are not in the app. With none of the three,
// none of this is, and the four answer as PHWUnknownStrategy.

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

// The kind `permission` asks for; its key is nil when this build left its
// prompt out.
static PHWEventsKind _kind(PHWPermission permission) {
    switch (permission) {
#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES) || PERMISSION_EVENTS_FULL_ACCESS
        case PHWPermissionCalendar:
        case PHWPermissionCalendarFullAccess:
            return (PHWEventsKind){@"NSCalendarsFullAccessUsageDescription",
                                   @selector(requestFullAccessToEventsWithCompletion:)};
#endif
#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES) || PERMISSION_EVENTS || \
    PERMISSION_EVENTS_FULL_ACCESS
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
    PHWEventsKind kind = _kind(permission);
    if (kind.key == nil) {
        // Its prompt is left out: no key the app's Info.plist sets allows it.
        // The iOS implementation answers denied here too.
        done(PHWStatusDenied);
        return;
    }
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

Class phw_events_strategy(void) {
    return [PHWEventsStrategy class];
}

#else

Class phw_events_strategy(void) {
    return [PHWUnknownStrategy class];
}

#endif
