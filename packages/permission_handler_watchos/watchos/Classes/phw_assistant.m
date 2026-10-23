// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
//
// Siri, through INPreferences (watchOS 6 and later), answered as the iOS
// implementation answers it. Intents is loaded at runtime and only messaged.
//
// INPreferences throws, ending the app, in a process without the Siri
// entitlement, and the exception leaves its dispatch_once unfinished, so it
// cannot be caught and asked again. The iOS implementation only compiles this
// in when the app sets PERMISSION_ASSISTANT; here NSSiriUsageDescription in
// the Info.plist, which a Siri request needs anyway, is that opt-in. Without
// it the status is denied and a request fails as a missing key.

#import "phw_internal.h"

#import <Intents/Intents.h>
#import <objc/message.h>

static PHWStatus _assistantStatus(NSInteger status) {
    switch ((INSiriAuthorizationStatus)status) {
        case INSiriAuthorizationStatusAuthorized:
            return PHWStatusGranted;
        case INSiriAuthorizationStatusRestricted:
            return PHWStatusRestricted;
        case INSiriAuthorizationStatusDenied:
            return PHWStatusPermanentlyDenied;
        case INSiriAuthorizationStatusNotDetermined:
            return PHWStatusDenied;
    }
    return PHWStatusDenied;
}

@implementation PHWAssistantStrategy

- (Class)preferencesClass {
    return phw_class(@"Intents", @"INPreferences");
}

- (void)checkPermission:(PHWPermission)permission done:(PHWStatusHandler)done {
    Class preferences = phw_has_key(@"NSSiriUsageDescription") ? [self preferencesClass] : nil;
    done(preferences == nil
             ? PHWStatusDenied
             : _assistantStatus(phw_class_integer(preferences, @selector(siriAuthorizationStatus))));
}

- (void)checkService:(PHWPermission)permission
                done:(PHWServiceHandler)done
              failed:(PHWErrorHandler)failed {
    done(PHWServiceNotApplicable);
}

- (void)requestPermission:(PHWPermission)permission
                     done:(PHWStatusHandler)done
                   failed:(PHWErrorHandler)failed {
    if (!phw_has_key(@"NSSiriUsageDescription")) {
        phw_missing_key(@"NSSiriUsageDescription", failed);
        return;
    }
    Class preferences = [self preferencesClass];
    if (preferences == nil) {
        done(PHWStatusPermanentlyDenied);
        return;
    }
    PHWStatus status =
        _assistantStatus(phw_class_integer(preferences, @selector(siriAuthorizationStatus)));
    if (status != PHWStatusDenied) {
        done(status);
        return;
    }
    ((void (*)(Class, SEL, void (^)(INSiriAuthorizationStatus)))objc_msgSend)(
        preferences, @selector(requestSiriAuthorization:), ^(INSiriAuthorizationStatus answer) {
            done(_assistantStatus(answer));
        });
}

@end
