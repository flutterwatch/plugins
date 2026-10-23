// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
//
// The microphone, through AVAudioApplication's record permission. AVFAudio
// is loaded at runtime and only messaged.

#import "phw_internal.h"

#import <AVFAudio/AVFAudio.h>
#import <objc/message.h>

static PHWStatus _recordStatus(NSInteger permission) {
    switch ((AVAudioApplicationRecordPermission)permission) {
        case AVAudioApplicationRecordPermissionUndetermined:
            return PHWStatusDenied;
        case AVAudioApplicationRecordPermissionDenied:
            return PHWStatusPermanentlyDenied;
        case AVAudioApplicationRecordPermissionGranted:
            return PHWStatusGranted;
    }
    return PHWStatusDenied;
}

@implementation PHWMicrophoneStrategy

- (Class)applicationClass {
    return phw_class(@"AVFAudio", @"AVAudioApplication");
}

- (PHWStatus)status {
    id application = ((id (*)(Class, SEL))objc_msgSend)([self applicationClass],
                                                          @selector(sharedInstance));
    return _recordStatus(((NSInteger (*)(id, SEL))objc_msgSend)(application,
                                                                 @selector(recordPermission)));
}

- (void)checkPermission:(PHWPermission)permission done:(PHWStatusHandler)done {
    done([self applicationClass] == nil ? PHWStatusDenied : [self status]);
}

- (void)checkService:(PHWPermission)permission
                done:(PHWServiceHandler)done
              failed:(PHWErrorHandler)failed {
    done(PHWServiceNotApplicable);
}

- (void)requestPermission:(PHWPermission)permission
                     done:(PHWStatusHandler)done
                   failed:(PHWErrorHandler)failed {
    Class applicationClass = [self applicationClass];
    if (applicationClass == nil) {
        done(PHWStatusPermanentlyDenied);
        return;
    }
    PHWStatus status = [self status];
    if (status != PHWStatusDenied) {
        done(status);
        return;
    }
    if (!phw_has_key(@"NSMicrophoneUsageDescription")) {
        phw_missing_key(@"NSMicrophoneUsageDescription", failed);
        return;
    }
    ((void (*)(Class, SEL, void (^)(BOOL)))objc_msgSend)(
        applicationClass, @selector(requestRecordPermissionWithCompletionHandler:),
        ^(BOOL granted) {
            done(granted ? PHWStatusGranted : PHWStatusPermanentlyDenied);
        });
}

@end
