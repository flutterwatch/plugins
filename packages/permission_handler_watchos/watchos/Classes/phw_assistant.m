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
// in when the app sets PERMISSION_ASSISTANT. Here the opt-in is the
// Info.plist key below, set to YES, which an app adds only with the Siri
// capability. A usage description alone does not switch it on: an app built
// by a flutter-watchos that predates `defines` adds every group's.
//
// The same key turns PERMISSION_ASSISTANT on under a flutter-watchos that
// applies `defines`, so without it none of this is in the app and Siri
// answers as PHWUnknownStrategy. An older flutter-watchos compiles this in
// for every app, so the key is still read here. It is read by the CLI's rule,
// so the two always agree: any non-empty string, NO included, opts in, as the
// Boolean YES does. Without the opt-in, Siri is never asked about, the status
// is denied, and so is a request.

#import "phw_internal.h"

#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES) || PERMISSION_ASSISTANT

#import <Intents/Intents.h>
#import <objc/message.h>

// The Info.plist key, a Boolean, that says the app has the Siri capability.
static NSString* const kSiriOptIn = @"PermissionHandlerWatchosSiri";

static BOOL _optedIn(void) {
    return phw_turns_on([[NSBundle mainBundle] objectForInfoDictionaryKey:kSiriOptIn]);
}

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

@interface PHWAssistantStrategy : NSObject <PHWStrategy>
@end

@implementation PHWAssistantStrategy

- (Class)preferencesClass {
    return phw_class(@"Intents", @"INPreferences");
}

- (void)checkPermission:(PHWPermission)permission done:(PHWStatusHandler)done {
    Class preferences = _optedIn() ? [self preferencesClass] : nil;
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
    if (!_optedIn()) {
        done(PHWStatusDenied);
        return;
    }
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

Class phw_assistant_strategy(void) {
    return [PHWAssistantStrategy class];
}

#else

Class phw_assistant_strategy(void) {
    return [PHWUnknownStrategy class];
}

#endif
