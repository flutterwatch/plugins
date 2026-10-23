// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
//
// Notifications and critical alerts, through UNUserNotificationCenter,
// answered as the iOS implementation answers them. The only framework this
// package links: it needs no usage description.

#import "phw_internal.h"

#import <UserNotifications/UserNotifications.h>

static PHWStatus _notificationStatus(UNAuthorizationStatus status) {
    switch (status) {
        case UNAuthorizationStatusNotDetermined:
            return PHWStatusDenied;
        case UNAuthorizationStatusDenied:
            return PHWStatusPermanentlyDenied;
        case UNAuthorizationStatusProvisional:
            return PHWStatusProvisional;
        default:
            // Authorized, and ephemeral for an App Clip.
            return PHWStatusGranted;
    }
}

@implementation PHWNotificationStrategy

- (void)checkPermission:(PHWPermission)permission done:(PHWStatusHandler)done {
    [[UNUserNotificationCenter currentNotificationCenter]
        getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings) {
        done(_notificationStatus(settings.authorizationStatus));
    }];
}

- (void)checkService:(PHWPermission)permission
                done:(PHWServiceHandler)done
              failed:(PHWErrorHandler)failed {
    done(PHWServiceNotApplicable);
}

- (void)requestPermission:(PHWPermission)permission
                     done:(PHWStatusHandler)done
                   failed:(PHWErrorHandler)failed {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings) {
        PHWStatus status = _notificationStatus(settings.authorizationStatus);
        // Provisional can still be raised to full authorization.
        if (status != PHWStatusDenied && status != PHWStatusProvisional) {
            done(status);
            return;
        }
        UNAuthorizationOptions options = UNAuthorizationOptionAlert |
                                         UNAuthorizationOptionSound |
                                         UNAuthorizationOptionBadge;
        [center requestAuthorizationWithOptions:options
                              completionHandler:^(BOOL granted, NSError* error) {
            done(granted && error == nil ? PHWStatusGranted : PHWStatusPermanentlyDenied);
        }];
    }];
}

@end

// What the iOS implementation reads from criticalAlertSetting: on, off, and
// not supported, which an app without the Critical Alerts entitlement gets.
static PHWStatus _criticalStatus(UNNotificationSettings* settings) {
    switch (settings.criticalAlertSetting) {
        case UNNotificationSettingEnabled:
            return PHWStatusGranted;
        case UNNotificationSettingDisabled:
            return PHWStatusPermanentlyDenied;
        default:
            return PHWStatusDenied;
    }
}

@implementation PHWCriticalAlertsStrategy

- (void)checkPermission:(PHWPermission)permission done:(PHWStatusHandler)done {
    [[UNUserNotificationCenter currentNotificationCenter]
        getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings) {
        done(_criticalStatus(settings));
    }];
}

- (void)checkService:(PHWPermission)permission
                done:(PHWServiceHandler)done
              failed:(PHWErrorHandler)failed {
    done(PHWServiceNotApplicable);
}

- (void)requestPermission:(PHWPermission)permission
                     done:(PHWStatusHandler)done
                   failed:(PHWErrorHandler)failed {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings) {
        PHWStatus status = _criticalStatus(settings);
        if (status != PHWStatusDenied) {
            done(status);
            return;
        }
        [center requestAuthorizationWithOptions:UNAuthorizationOptionCriticalAlert
                              completionHandler:^(BOOL granted, NSError* error) {
            done(granted && error == nil ? PHWStatusGranted : PHWStatusPermanentlyDenied);
        }];
    }];
}

@end
