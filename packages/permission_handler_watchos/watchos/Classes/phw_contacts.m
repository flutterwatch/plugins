// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Contacts, through CNContactStore. Contacts is loaded at runtime and only
// messaged.

#import "phw_internal.h"

#import <Contacts/Contacts.h>

static PHWStatus _contactsStatus(NSInteger status) {
    switch (status) {
        case CNAuthorizationStatusNotDetermined:
            return PHWStatusDenied;
        case CNAuthorizationStatusRestricted:
            return PHWStatusRestricted;
        case CNAuthorizationStatusDenied:
            return PHWStatusPermanentlyDenied;
        case CNAuthorizationStatusAuthorized:
            return PHWStatusGranted;
        default:
            // CNAuthorizationStatusLimited, from watchOS 11.
            return PHWStatusLimited;
    }
}

@implementation PHWContactsStrategy {
    // Kept until its request answers.
    CNContactStore* _store;
}

- (Class)storeClass {
    return phw_class(@"Contacts", @"CNContactStore");
}

- (PHWStatus)statusOf:(Class)storeClass {
    return _contactsStatus(phw_class_integer_with(
        storeClass, @selector(authorizationStatusForEntityType:), CNEntityTypeContacts));
}

- (void)checkPermission:(PHWPermission)permission done:(PHWStatusHandler)done {
    Class storeClass = [self storeClass];
    done(storeClass == nil ? PHWStatusDenied : [self statusOf:storeClass]);
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
    PHWStatus status = [self statusOf:storeClass];
    if (status != PHWStatusDenied) {
        done(status);
        return;
    }
    if (!phw_has_key(@"NSContactsUsageDescription")) {
        phw_missing_key(@"NSContactsUsageDescription", failed);
        return;
    }
    _store = [[storeClass alloc] init];
    [_store requestAccessForEntityType:CNEntityTypeContacts
                     completionHandler:^(BOOL granted, NSError* error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_store = nil;
            done(granted ? [self statusOf:storeClass] : PHWStatusPermanentlyDenied);
        });
    }];
}

@end
