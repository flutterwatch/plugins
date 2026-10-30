// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
//
// What the strategy files share. Nothing here is exported to Dart.

#ifndef PHW_INTERNAL_H
#define PHW_INTERNAL_H

#import <Foundation/Foundation.h>

// Shared between this package's files only, never with the rest of the app.
#define PHW_HIDDEN __attribute__((visibility("hidden")))

// permission_handler's numbers for the permissions watchOS has.
typedef NS_ENUM(int, PHWPermission) {
    PHWPermissionCalendar = 0,
    PHWPermissionContacts = 2,
    PHWPermissionLocation = 3,
    PHWPermissionLocationAlways = 4,
    PHWPermissionLocationWhenInUse = 5,
    PHWPermissionMicrophone = 7,
    PHWPermissionReminders = 11,
    PHWPermissionSensors = 12,
    PHWPermissionStorage = 15,
    PHWPermissionNotification = 17,
    PHWPermissionBluetooth = 21,
    PHWPermissionCriticalAlerts = 26,
    PHWPermissionCalendarWriteOnly = 36,
    PHWPermissionCalendarFullAccess = 37,
    PHWPermissionAssistant = 38,
};

// PermissionStatus.
typedef NS_ENUM(int, PHWStatus) {
    PHWStatusDenied = 0,
    PHWStatusGranted = 1,
    PHWStatusRestricted = 2,
    PHWStatusLimited = 3,
    PHWStatusPermanentlyDenied = 4,
    PHWStatusProvisional = 5,
};

// ServiceStatus.
typedef NS_ENUM(int, PHWService) {
    PHWServiceDisabled = 0,
    PHWServiceEnabled = 1,
    PHWServiceNotApplicable = 2,
};

typedef void (^PHWStatusHandler)(PHWStatus status);
typedef void (^PHWServiceHandler)(PHWService service);
typedef void (^PHWErrorHandler)(NSString* code, NSString* message);

// One group of permissions. Its methods are called on the main queue, and
// each calls one of its handlers once, from any queue.
@protocol PHWStrategy <NSObject>
- (void)checkPermission:(PHWPermission)permission done:(PHWStatusHandler)done;
- (void)checkService:(PHWPermission)permission
                done:(PHWServiceHandler)done
              failed:(PHWErrorHandler)failed;
- (void)requestPermission:(PHWPermission)permission
                     done:(PHWStatusHandler)done
                   failed:(PHWErrorHandler)failed;
@end

// The class `className` of the system framework `framework`, loaded on first
// use, or nil when this watchOS has neither. No framework but
// UserNotifications is linked, so an app does not load the frameworks of the
// permissions it never asks about. The class names and selectors are still
// in the binary: unlike the iOS implementation's opt-in macros, this does
// not take a group's code out of the app.
PHW_HIDDEN Class phw_class(NSString* framework, NSString* className);

// Whether the app's Info.plist has `key`.
PHW_HIDDEN BOOL phw_has_key(NSString* key);

// Fails with MISSING_USAGE_DESCRIPTION, naming `key`.
PHW_HIDDEN void phw_missing_key(NSString* key, PHWErrorHandler failed);

// Sends a class method with no argument that returns an integer.
PHW_HIDDEN NSInteger phw_class_integer(Class cls, SEL selector);

// Sends a class method with one integer argument that returns an integer.
PHW_HIDDEN NSInteger phw_class_integer_with(Class cls, SEL selector, NSInteger argument);

// Sends a class method with no argument that returns a BOOL.
PHW_HIDDEN BOOL phw_class_bool(Class cls, SEL selector);

// What answers for the permissions watchOS does not have: as the iOS
// implementation answers for an unknown permission.
@interface PHWUnknownStrategy : NSObject <PHWStrategy>
@end

@interface PHWNotificationStrategy : NSObject <PHWStrategy>
@end

@interface PHWLocationStrategy : NSObject <PHWStrategy>
@end

@interface PHWMotionStrategy : NSObject <PHWStrategy>
@end

@interface PHWMicrophoneStrategy : NSObject <PHWStrategy>
@end

@interface PHWContactsStrategy : NSObject <PHWStrategy>
@end

@interface PHWEventsStrategy : NSObject <PHWStrategy>
@end

@interface PHWBluetoothStrategy : NSObject <PHWStrategy>
@end

// Storage, granted as on iOS: the app's own container needs no permission.
@interface PHWStorageStrategy : NSObject <PHWStrategy>
@end

@interface PHWCriticalAlertsStrategy : NSObject <PHWStrategy>
@end

@interface PHWAssistantStrategy : NSObject <PHWStrategy>
@end

#endif  // PHW_INTERNAL_H
