// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "firebase_messaging_watchos_ffi.h"

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import <WatchKit/WatchKit.h>

@import FirebaseCore;
@import FirebaseMessaging;

#include <stdlib.h>

// Notification names posted by the flutter-watchos runner's
// FlutterWatchOSAppDelegate (the app-level WKApplicationDelegate — the only
// place watchOS delivers these callbacks). Observed by literal name: the
// plugin has no compile-time dependency on the host module.
static NSString *const kDidRegisterNotification =
    @"FlutterWatchOSRemoteNotificationsDidRegister";
static NSString *const kDidFailNotification =
    @"FlutterWatchOSRemoteNotificationsDidFail";
static NSString *const kDidReceiveNotification =
    @"FlutterWatchOSRemoteNotificationDidReceive";

#pragma mark - JSON helpers

// Serializes a JSON-compatible object to a freshly heap-allocated UTF-8 C
// string. Ownership transfers to the caller (Dart), which releases it with
// `firebase_messaging_watchos_free`.
static const char *FMWCopy(id jsonObject) {
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

static id FMWOrNull(id value) {
    return value ?: (id)[NSNull null];
}

static NSString *FMWStr(NSDictionary *map, NSString *key) {
    id value = map[key];
    if (value == nil || value == (id)[NSNull null] || ![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    return value;
}

static NSDictionary *FMWSimpleError(NSString *message, NSString *code) {
    return @{@"error" : message ?: @"unknown", @"code" : code ?: @"unknown"};
}

static const char *FMWCopyError(NSString *message, NSString *code) {
    return FMWCopy(FMWSimpleError(message, code));
}

static NSDictionary *FMWErrorDict(NSError *error) {
    return @{
        @"error" : error.localizedDescription ?: @"unknown",
        @"code" : @"unknown",
    };
}

static NSString *FMWHex(NSData *data) {
    if (data == nil) {
        return nil;
    }
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    const unsigned char *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return hex;
}

#pragma mark - Message serialization

// Builds a `RemoteMessage.fromMap`-shaped map from an APNs payload.
static NSDictionary *FMWMessageFromPayload(NSDictionary *userInfo) {
    NSDictionary *aps = [userInfo[@"aps"] isKindOfClass:[NSDictionary class]]
        ? userInfo[@"aps"]
        : @{};
    // Everything that is not an APNs/FCM reserved key is message data.
    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    for (id key in userInfo) {
        if (![key isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *name = key;
        if ([name isEqualToString:@"aps"] || [name hasPrefix:@"gcm."] ||
            [name hasPrefix:@"google."] || [name isEqualToString:@"fcm_options"]) {
            continue;
        }
        id value = userInfo[key];
        if ([NSJSONSerialization isValidJSONObject:@{@"v" : value}]) {
            data[name] = value;
        } else if ([value isKindOfClass:[NSString class]] ||
                   [value isKindOfClass:[NSNumber class]]) {
            data[name] = value;
        }
    }

    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    map[@"messageId"] = FMWOrNull(userInfo[@"gcm.message_id"]);
    map[@"from"] = FMWOrNull(userInfo[@"from"]);
    map[@"category"] = FMWOrNull(aps[@"category"]);
    map[@"threadId"] = FMWOrNull(aps[@"thread-id"]);
    map[@"contentAvailable"] = @([aps[@"content-available"] boolValue]);
    map[@"data"] = data;

    id alert = aps[@"alert"];
    if ([alert isKindOfClass:[NSString class]]) {
        map[@"notification"] = @{@"title" : [NSNull null], @"body" : alert};
    } else if ([alert isKindOfClass:[NSDictionary class]]) {
        map[@"notification"] = @{
            @"title" : FMWOrNull(alert[@"title"]),
            @"body" : FMWOrNull(alert[@"body"]),
        };
    }
    return map;
}

#pragma mark - Shared state

// Central plugin state: APNs/FCM token tracking (fed by the runner-delegate
// notifications and the FIRMessaging delegate) and the received-message
// queues (fed by the UNUserNotificationCenter delegate).
@interface FMWState : NSObject <FIRMessagingDelegate, UNUserNotificationCenterDelegate>
@property(atomic, assign) int64_t tokenGeneration;
@property(atomic, copy) NSString *fcmToken;
@property(atomic, copy) NSData *apnsToken;
@property(atomic, copy) NSString *apnsError;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *foregroundMessages;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *openedMessages;
@property(nonatomic, strong) NSDictionary *initialMessage;
@property(atomic, assign) UNNotificationPresentationOptions presentationOptions;
@property(nonatomic, strong) NSDate *startedAt;
@end

@implementation FMWState

+ (FMWState *)shared {
    static FMWState *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[FMWState alloc] init];
        shared.foregroundMessages = [NSMutableArray array];
        shared.openedMessages = [NSMutableArray array];
        shared.presentationOptions = UNNotificationPresentationOptionNone;
        shared.startedAt = [NSDate date];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:shared
                   selector:@selector(onDidRegister:)
                       name:kDidRegisterNotification
                     object:nil];
        [center addObserver:shared
                   selector:@selector(onDidFail:)
                       name:kDidFailNotification
                     object:nil];
        [center addObserver:shared
                   selector:@selector(onDidReceive:)
                       name:kDidReceiveNotification
                     object:nil];
        [UNUserNotificationCenter currentNotificationCenter].delegate = shared;
    });
    return shared;
}

- (void)onDidRegister:(NSNotification *)notification {
    NSData *token = notification.userInfo[@"deviceToken"];
    if (![token isKindOfClass:[NSData class]]) {
        return;
    }
    self.apnsToken = token;
    self.apnsError = nil;
    if ([FIRApp defaultApp] != nil) {
        [FIRMessaging messaging].APNSToken = token;
    }
}

- (void)onDidFail:(NSNotification *)notification {
    NSError *error = notification.userInfo[@"error"];
    self.apnsError = [error isKindOfClass:[NSError class]]
        ? error.localizedDescription
        : @"APNs registration failed.";
}

- (void)onDidReceive:(NSNotification *)notification {
    NSDictionary *payload = notification.userInfo;
    if (payload == nil) {
        return;
    }
    @synchronized(self) {
        [self.foregroundMessages addObject:FMWMessageFromPayload(payload)];
    }
}

// FIRMessagingDelegate ----------------------------------------------------

- (void)messaging:(FIRMessaging *)messaging
    didReceiveRegistrationToken:(NSString *)fcmToken {
    self.fcmToken = fcmToken;
    self.tokenGeneration += 1;
}

// UNUserNotificationCenterDelegate ---------------------------------------

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:
             (void (^)(UNNotificationPresentationOptions))completionHandler {
    NSDictionary *payload = notification.request.content.userInfo;
    @synchronized(self) {
        [self.foregroundMessages addObject:FMWMessageFromPayload(payload)];
    }
    completionHandler(self.presentationOptions);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler {
    NSDictionary *payload = response.notification.request.content.userInfo;
    NSDictionary *message = FMWMessageFromPayload(payload);
    @synchronized(self) {
        // A tap that arrives right after process start launched the app: that
        // is the "initial message" (getInitialMessage), not an
        // onMessageOpenedApp event.
        if (self.initialMessage == nil &&
            -[self.startedAt timeIntervalSinceNow] < 8.0) {
            self.initialMessage = message;
        } else {
            [self.openedMessages addObject:message];
        }
    }
    completionHandler();
}

@end

#pragma mark - Async operation registry

static NSMutableDictionary<NSNumber *, NSDictionary *> *FMWResults(void) {
    static NSMutableDictionary *results;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ results = [NSMutableDictionary dictionary]; });
    return results;
}

static int64_t FMWNextToken(void) {
    static int64_t next = 1;
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [[NSObject alloc] init]; });
    @synchronized(lock) {
        return next++;
    }
}

static void FMWComplete(int64_t token, NSDictionary *result) {
    NSMutableDictionary *results = FMWResults();
    @synchronized(results) {
        results[@(token)] = result;
    }
}

static void (^FMWOkCompletion(int64_t token))(NSError *) {
    return ^(NSError *error) {
        if (error != nil) {
            FMWComplete(token, FMWErrorDict(error));
        } else {
            FMWComplete(token, @{@"ok" : @YES});
        }
    };
}

#pragma mark - Messaging access

// Returns the FIRMessaging singleton (installing the token delegate on first
// use), or nil with `*errorOut` set if no Firebase app is configured.
static FIRMessaging *FMWMessaging(NSDictionary **errorOut) {
    if ([FIRApp defaultApp] == nil) {
        if (errorOut != NULL) {
            *errorOut = FMWSimpleError(
                @"No Firebase App has been created - call Firebase.initializeApp()",
                @"no-app");
        }
        return nil;
    }
    FIRMessaging *messaging = [FIRMessaging messaging];
    FMWState *state = [FMWState shared];
    if (messaging.delegate != (id<FIRMessagingDelegate>)state) {
        messaging.delegate = state;
        if (state.apnsToken != nil) {
            messaging.APNSToken = state.apnsToken;
        }
    }
    return messaging;
}

#pragma mark - Notification settings

static NSDictionary *FMWSettingsMap(UNNotificationSettings *settings) {
    // UNNotificationSetting raw values: 0 notSupported, 1 disabled,
    // 2 enabled. -1 marks capabilities watchOS does not expose at all.
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    map[@"authorizationStatus"] = @(settings.authorizationStatus);
    map[@"alert"] = @(settings.alertSetting);
    map[@"sound"] = @(settings.soundSetting);
    map[@"notificationCenter"] = @(settings.notificationCenterSetting);
    map[@"criticalAlert"] = @(settings.criticalAlertSetting);
    map[@"badge"] = @(-1);
    map[@"carPlay"] = @(-1);
    map[@"lockScreen"] = @(-1);
    map[@"showPreviews"] = @(-1);
    map[@"providesAppNotificationSettings"] = @(-1);
    map[@"announcement"] = @(-1);
    map[@"timeSensitive"] = @(-1);
    if (@available(watchOS 6.0, *)) {
        map[@"announcement"] = @(settings.announcementSetting);
    }
    if (@available(watchOS 8.0, *)) {
        map[@"timeSensitive"] = @(settings.timeSensitiveSetting);
    }
    return map;
}

#pragma mark - Operation dispatch

static BOOL FMWStartOp(NSString *op,
                       NSDictionary *request,
                       int64_t token,
                       NSDictionary **errorOut) {
    UNUserNotificationCenter *center =
        [UNUserNotificationCenter currentNotificationCenter];
    if ([op isEqualToString:@"requestPermission"]) {
        UNAuthorizationOptions options = 0;
        if ([request[@"alert"] boolValue]) { options |= UNAuthorizationOptionAlert; }
        if ([request[@"badge"] boolValue]) { options |= UNAuthorizationOptionBadge; }
        if ([request[@"sound"] boolValue]) { options |= UNAuthorizationOptionSound; }
        if ([request[@"criticalAlert"] boolValue]) {
            options |= UNAuthorizationOptionCriticalAlert;
        }
        if ([request[@"provisional"] boolValue]) {
            options |= UNAuthorizationOptionProvisional;
        }
        if (@available(watchOS 6.0, *)) {
            if ([request[@"announcement"] boolValue]) {
                options |= UNAuthorizationOptionAnnouncement;
            }
        }
        [center requestAuthorizationWithOptions:options
                              completionHandler:^(BOOL granted, NSError *error) {
            if (error != nil) {
                FMWComplete(token, FMWErrorDict(error));
                return;
            }
            [center getNotificationSettingsWithCompletionHandler:
                        ^(UNNotificationSettings *settings) {
                FMWComplete(token, @{@"settings" : FMWSettingsMap(settings)});
            }];
        }];
        return YES;
    }
    if ([op isEqualToString:@"getNotificationSettings"]) {
        [center getNotificationSettingsWithCompletionHandler:
                    ^(UNNotificationSettings *settings) {
            FMWComplete(token, @{@"settings" : FMWSettingsMap(settings)});
        }];
        return YES;
    }

    // The remaining ops need the Firebase SDK.
    FIRMessaging *messaging = FMWMessaging(errorOut);
    if (messaging == nil) {
        return NO;
    }
    if ([op isEqualToString:@"getToken"]) {
        [messaging tokenWithCompletion:^(NSString *fcmToken, NSError *error) {
            if (error != nil) {
                FMWComplete(token, FMWErrorDict(error));
            } else {
                FMWState *state = [FMWState shared];
                if (![state.fcmToken isEqualToString:fcmToken]) {
                    state.fcmToken = fcmToken;
                    state.tokenGeneration += 1;
                }
                FMWComplete(token, @{@"fcmToken" : FMWOrNull(fcmToken)});
            }
        }];
        return YES;
    }
    if ([op isEqualToString:@"deleteToken"]) {
        [messaging deleteTokenWithCompletion:FMWOkCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"subscribeToTopic"]) {
        [messaging subscribeToTopic:FMWStr(request, @"topic") ?: @""
                         completion:FMWOkCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"unsubscribeFromTopic"]) {
        [messaging unsubscribeFromTopic:FMWStr(request, @"topic") ?: @""
                             completion:FMWOkCompletion(token)];
        return YES;
    }
    if (errorOut != NULL) {
        *errorOut = FMWSimpleError(
            [NSString stringWithFormat:@"Unsupported messaging operation \"%@\".", op],
            @"unimplemented");
    }
    return NO;
}

#pragma mark - Exported FFI

const char *firebase_messaging_watchos_begin(const char *request_json) {
    @autoreleasepool {
        [FMWState shared];
        if (request_json == NULL) {
            return FMWCopyError(@"Request JSON is null.", @"invalid-argument");
        }
        NSData *data = [@(request_json) dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *request =
            [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![request isKindOfClass:[NSDictionary class]]) {
            return FMWCopyError(@"Request JSON is malformed.", @"invalid-argument");
        }
        NSString *op = FMWStr(request, @"op");
        if (op == nil) {
            return FMWCopyError(@"Request is missing \"op\".", @"invalid-argument");
        }
        int64_t token = FMWNextToken();
        NSDictionary *error = nil;
        if (!FMWStartOp(op, request, token, &error)) {
            return FMWCopy(error);
        }
        return FMWCopy(@{@"token" : @(token)});
    }
}

const char *firebase_messaging_watchos_poll(int64_t token) {
    @autoreleasepool {
        NSDictionary *result = nil;
        NSMutableDictionary *results = FMWResults();
        @synchronized(results) {
            result = results[@(token)];
            if (result != nil) {
                [results removeObjectForKey:@(token)];
            }
        }
        return FMWCopy(result ?: @{@"pending" : @YES});
    }
}

const char *firebase_messaging_watchos_state(void) {
    @autoreleasepool {
        FMWState *state = [FMWState shared];
        return FMWCopy(@{
            @"tokenGeneration" : @(state.tokenGeneration),
            @"fcmToken" : FMWOrNull(state.fcmToken),
            @"apnsToken" : FMWOrNull(FMWHex(state.apnsToken)),
            @"apnsError" : FMWOrNull(state.apnsError),
        });
    }
}

const char *firebase_messaging_watchos_take_messages(const char *kind) {
    @autoreleasepool {
        FMWState *state = [FMWState shared];
        NSString *name = kind != NULL ? @(kind) : @"";
        if ([name isEqualToString:@"initial"]) {
            NSDictionary *message;
            @synchronized(state) {
                message = state.initialMessage;
                state.initialMessage = nil;
            }
            return FMWCopy(@{@"message" : FMWOrNull(message)});
        }
        NSMutableArray<NSDictionary *> *queue =
            [name isEqualToString:@"opened"] ? state.openedMessages
                                             : state.foregroundMessages;
        NSArray *drained;
        @synchronized(state) {
            drained = [queue copy];
            [queue removeAllObjects];
        }
        return FMWCopy(@{@"messages" : drained});
    }
}

const char *firebase_messaging_watchos_configure(const char *request_json) {
    @autoreleasepool {
        [FMWState shared];
        if (request_json == NULL) {
            return FMWCopyError(@"Request JSON is null.", @"invalid-argument");
        }
        NSData *data = [@(request_json) dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *request =
            [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![request isKindOfClass:[NSDictionary class]]) {
            return FMWCopyError(@"Request JSON is malformed.", @"invalid-argument");
        }
        NSString *op = FMWStr(request, @"op") ?: @"";
        if ([op isEqualToString:@"registerForRemoteNotifications"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[WKApplication sharedApplication] registerForRemoteNotifications];
            });
            return FMWCopy(@{@"ok" : @YES});
        }
        if ([op isEqualToString:@"setForegroundPresentation"]) {
            UNNotificationPresentationOptions options =
                UNNotificationPresentationOptionNone;
            if ([request[@"alert"] boolValue]) {
                options |= UNNotificationPresentationOptionBanner;
            }
            if ([request[@"sound"] boolValue]) {
                options |= UNNotificationPresentationOptionSound;
            }
            [FMWState shared].presentationOptions = options;
            return FMWCopy(@{@"ok" : @YES});
        }
        NSDictionary *error = nil;
        FIRMessaging *messaging = FMWMessaging(&error);
        if (messaging == nil) {
            return FMWCopy(error);
        }
        if ([op isEqualToString:@"setAutoInit"]) {
            messaging.autoInitEnabled = [request[@"enabled"] boolValue];
            return FMWCopy(@{@"ok" : @YES});
        }
        if ([op isEqualToString:@"getAutoInit"]) {
            return FMWCopy(@{@"enabled" : @(messaging.isAutoInitEnabled)});
        }
        return FMWCopyError(
            [NSString stringWithFormat:@"Unknown configure op \"%@\".", op],
            @"invalid-argument");
    }
}

void firebase_messaging_watchos_free(const char *ptr) {
    if (ptr != NULL) {
        free((void *)ptr);
    }
}
