// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "firebase_core_watchos_ffi.h"

#import <Foundation/Foundation.h>

@import FirebaseCore;

#include <stdlib.h>

// The Dart-side default app name (`defaultFirebaseAppName`). The Apple SDK
// names its default app "__FIRAPP_DEFAULT"; we translate between the two so
// the Dart layer only ever sees "[DEFAULT]".
static NSString *const kDartDefaultName = @"[DEFAULT]";
static NSString *const kFIRDefaultName = @"__FIRAPP_DEFAULT";

#pragma mark - Helpers

// Serializes a JSON-compatible object to a freshly heap-allocated UTF-8 C
// string. Ownership transfers to the caller (Dart), which releases it with
// `firebase_core_watchos_free`.
static const char *FCWCopy(id jsonObject) {
    @autoreleasepool {
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:jsonObject
                                                       options:0
                                                         error:&error];
        if (data == nil) {
            return strdup("{\"error\":\"json-encode-failed\",\"code\":\"internal\"}");
        }
        NSString *string = [[NSString alloc] initWithData:data
                                                 encoding:NSUTF8StringEncoding];
        return strdup(string.UTF8String);
    }
}

static const char *FCWError(NSString *message, NSString *code) {
    return FCWCopy(@{@"error" : message ?: @"unknown", @"code" : code ?: @"unknown"});
}

// Reads a non-null, non-NSNull string from a decoded JSON map, or nil.
static NSString *FCWStr(NSDictionary *map, NSString *key) {
    id value = map[key];
    if (value == nil || value == (id)[NSNull null] || ![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    return value;
}

static BOOL FCWIsDefault(NSString *dartName) {
    return dartName.length == 0 || [dartName isEqualToString:kDartDefaultName];
}

static NSString *FCWDartName(NSString *firAppName) {
    return [firAppName isEqualToString:kFIRDefaultName] ? kDartDefaultName : firAppName;
}

static FIRApp *FCWLookup(NSString *dartName) {
    return FCWIsDefault(dartName) ? [FIRApp defaultApp] : [FIRApp appNamed:dartName];
}

// Builds a FIROptions from `FirebaseOptions.asMap`.
static FIROptions *FCWOptionsFromMap(NSDictionary *map) {
    NSString *appId = FCWStr(map, @"appId") ?: @"";
    NSString *sender = FCWStr(map, @"messagingSenderId") ?: @"";
    FIROptions *options = [[FIROptions alloc] initWithGoogleAppID:appId GCMSenderID:sender];
    options.APIKey = FCWStr(map, @"apiKey");
    options.projectID = FCWStr(map, @"projectId");
    NSString *databaseURL = FCWStr(map, @"databaseURL");
    if (databaseURL) { options.databaseURL = databaseURL; }
    NSString *storageBucket = FCWStr(map, @"storageBucket");
    if (storageBucket) { options.storageBucket = storageBucket; }
    NSString *clientID = FCWStr(map, @"iosClientId");
    if (clientID) { options.clientID = clientID; }
    NSString *bundleID = FCWStr(map, @"iosBundleId");
    options.bundleID = bundleID ?: [[NSBundle mainBundle] bundleIdentifier];
    NSString *deepLink = FCWStr(map, @"deepLinkURLScheme");
    if (deepLink) { options.deepLinkURLScheme = deepLink; }
    NSString *appGroupID = FCWStr(map, @"appGroupId");
    if (appGroupID) { options.appGroupID = appGroupID; }
    return options;
}

// Builds the `FirebaseOptions.asMap` shape from a native FIROptions. Uses
// NSNull for absent values so the JSON round-trips into a Dart map.
static NSDictionary *FCWOptionsToMap(FIROptions *options) {
    id (^orNull)(NSString *) = ^id(NSString *value) { return value ?: (id)[NSNull null]; };
    return @{
        @"apiKey" : orNull(options.APIKey),
        @"appId" : orNull(options.googleAppID),
        @"messagingSenderId" : orNull(options.GCMSenderID),
        @"projectId" : orNull(options.projectID),
        @"databaseURL" : orNull(options.databaseURL),
        @"storageBucket" : orNull(options.storageBucket),
        @"iosClientId" : orNull(options.clientID),
        @"iosBundleId" : orNull(options.bundleID),
        @"deepLinkURLScheme" : orNull(options.deepLinkURLScheme),
        @"appGroupId" : orNull(options.appGroupID),
    };
}

static NSDictionary *FCWAppInfo(FIRApp *app) {
    return @{
        @"name" : FCWDartName(app.name),
        @"options" : FCWOptionsToMap(app.options),
        @"isAutomaticDataCollectionEnabled" : @(app.isDataCollectionDefaultEnabled),
    };
}

#pragma mark - Exported FFI

const char *firebase_core_watchos_configure(const char *name, const char *options_json) {
    @autoreleasepool {
        NSString *dartName = name != NULL ? @(name) : @"";
        NSString *optionsStr = options_json != NULL ? @(options_json) : @"";
        BOOL isDefault = FCWIsDefault(dartName);

        // Idempotent: configuring an already-configured app returns it.
        FIRApp *existing = FCWLookup(dartName);
        if (existing != nil) {
            return FCWCopy(FCWAppInfo(existing));
        }

        FIROptions *options = nil;
        if (optionsStr.length > 0) {
            NSData *data = [optionsStr dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *map = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![map isKindOfClass:[NSDictionary class]]) {
                return FCWError(@"Firebase options JSON is malformed.", @"invalid-argument");
            }
            options = FCWOptionsFromMap(map);
        }

        @try {
            if (isDefault) {
                if (options != nil) {
                    [FIRApp configureWithOptions:options];
                } else {
                    // Configure the default app from a bundled
                    // GoogleService-Info.plist. Throws if none is present.
                    [FIRApp configure];
                }
            } else {
                if (options == nil) {
                    return FCWError(@"A named Firebase app requires options.", @"invalid-argument");
                }
                [FIRApp configureWithName:dartName options:options];
            }
        } @catch (NSException *exception) {
            return FCWError(exception.reason ?: @"Firebase configuration failed.",
                            @"configuration-failed");
        }

        FIRApp *app = FCWLookup(dartName);
        if (app == nil) {
            return FCWError(@"Firebase configuration produced no app.", @"no-app");
        }
        return FCWCopy(FCWAppInfo(app));
    }
}

const char *firebase_core_watchos_options(const char *name) {
    @autoreleasepool {
        NSString *dartName = name != NULL ? @(name) : @"";
        FIRApp *app = FCWLookup(dartName);
        if (app == nil) {
            return FCWError(@"No Firebase app configured with that name.", @"no-app");
        }
        return FCWCopy(FCWAppInfo(app));
    }
}

const char *firebase_core_watchos_apps(void) {
    @autoreleasepool {
        NSDictionary<NSString *, FIRApp *> *all = [FIRApp allApps];
        NSMutableArray *result = [NSMutableArray array];
        for (FIRApp *app in all.allValues) {
            [result addObject:FCWAppInfo(app)];
        }
        return FCWCopy(result);
    }
}

const char *firebase_core_watchos_delete(const char *name) {
    @autoreleasepool {
        NSString *dartName = name != NULL ? @(name) : @"";
        FIRApp *app = FCWLookup(dartName);
        if (app == nil) {
            return FCWError(@"No Firebase app configured with that name.", @"no-app");
        }
        // The Apple SDK forbids deleting the default app; report success to
        // match FlutterFire's behaviour on the Dart side.
        if (FCWIsDefault(dartName)) {
            return FCWCopy(@{@"deleted" : @NO});
        }
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block BOOL deleted = NO;
        [app deleteApp:^(BOOL success) {
            deleted = success;
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore,
                                dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
        return FCWCopy(@{@"deleted" : @(deleted)});
    }
}

const char *firebase_core_watchos_set_auto_data_collection(const char *name, bool enabled) {
    @autoreleasepool {
        NSString *dartName = name != NULL ? @(name) : @"";
        FIRApp *app = FCWLookup(dartName);
        if (app == nil) {
            return FCWError(@"No Firebase app configured with that name.", @"no-app");
        }
        app.dataCollectionDefaultEnabled = enabled ? YES : NO;
        return FCWCopy(@{@"ok" : @YES});
    }
}

void firebase_core_watchos_free(const char *ptr) {
    if (ptr != NULL) {
        free((void *)ptr);
    }
}
