// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "firebase_auth_watchos_ffi.h"

#import <Foundation/Foundation.h>

@import FirebaseAuth;
@import FirebaseCore;

#include <stdlib.h>

// The Dart-side default app name (`defaultFirebaseAppName`). The Apple SDK
// names its default app "__FIRAPP_DEFAULT"; we translate between the two so
// the Dart layer only ever sees "[DEFAULT]".
static NSString *const kDartDefaultName = @"[DEFAULT]";

#pragma mark - JSON helpers

// Serializes a JSON-compatible object to a freshly heap-allocated UTF-8 C
// string. Ownership transfers to the caller (Dart), which releases it with
// `firebase_auth_watchos_free`.
static const char *FAWCopy(id jsonObject) {
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

static id FAWOrNull(id value) {
    return value ?: (id)[NSNull null];
}

// Reads a non-null, non-NSNull string from a decoded JSON map, or nil.
static NSString *FAWStr(NSDictionary *map, NSString *key) {
    id value = map[key];
    if (value == nil || value == (id)[NSNull null] || ![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    return value;
}

#pragma mark - Errors

// Maps a FIRAuth NSError to the FlutterFire string code: the SDK attaches an
// "ERROR_SNAKE_CASE" name under its userInfo name key, which FlutterFire
// lowercases and dash-separates (ERROR_WRONG_PASSWORD -> wrong-password).
// The Swift-rewritten SDK exposes the keys as FIRAuthErrors class properties,
// not global constants.
static NSString *FAWErrorCode(NSError *error) {
    NSString *name = error.userInfo[FIRAuthErrors.userInfoNameKey];
    if (![name isKindOfClass:[NSString class]] || name.length == 0) {
        return @"unknown";
    }
    if ([name hasPrefix:@"ERROR_"]) {
        name = [name substringFromIndex:@"ERROR_".length];
    }
    return [[name lowercaseString] stringByReplacingOccurrencesOfString:@"_"
                                                             withString:@"-"];
}

static NSDictionary *FAWErrorDict(NSError *error) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:@{
        @"error" : error.localizedDescription ?: @"unknown",
        @"code" : FAWErrorCode(error),
    }];
    NSString *email = error.userInfo[FIRAuthErrors.userInfoEmailKey];
    if ([email isKindOfClass:[NSString class]]) {
        dict[@"email"] = email;
    }
    return dict;
}

static NSDictionary *FAWSimpleError(NSString *message, NSString *code) {
    return @{@"error" : message ?: @"unknown", @"code" : code ?: @"unknown"};
}

static const char *FAWCopyError(NSString *message, NSString *code) {
    return FAWCopy(FAWSimpleError(message, code));
}

#pragma mark - Auth lookup + change listeners

// Per-auth-instance change counters, bumped by the SDK's listener callbacks.
// The Dart side polls these to drive authStateChanges/idTokenChanges streams.
@interface FAWState : NSObject
@property(atomic, assign) int64_t authGeneration;
@property(atomic, assign) int64_t idTokenGeneration;
@property(nonatomic, strong) id authListenerHandle;
@property(nonatomic, strong) id idTokenListenerHandle;
@end

@implementation FAWState
@end

static NSMutableDictionary<NSString *, FAWState *> *FAWStates(void) {
    static NSMutableDictionary *states;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ states = [NSMutableDictionary dictionary]; });
    return states;
}

// Resolves the FIRAuth for a Dart app name (installing the change listeners
// on first use), or nil with `*errorOut` set if the app is not configured.
static FIRAuth *FAWAuth(NSString *dartName, NSDictionary **errorOut) {
    BOOL isDefault = dartName.length == 0 || [dartName isEqualToString:kDartDefaultName];
    FIRApp *app = isDefault ? [FIRApp defaultApp] : [FIRApp appNamed:dartName];
    if (app == nil) {
        if (errorOut != NULL) {
            *errorOut = FAWSimpleError(
                @"No Firebase App has been created - call Firebase.initializeApp()",
                @"no-app");
        }
        return nil;
    }
    FIRAuth *auth = [FIRAuth authWithApp:app];
    NSString *key = isDefault ? kDartDefaultName : dartName;
    NSMutableDictionary<NSString *, FAWState *> *states = FAWStates();
    @synchronized(states) {
        if (states[key] == nil) {
            FAWState *state = [[FAWState alloc] init];
            state.authListenerHandle =
                [auth addAuthStateDidChangeListener:^(FIRAuth *a, FIRUser *user) {
                    state.authGeneration += 1;
                }];
            state.idTokenListenerHandle =
                [auth addIDTokenDidChangeListener:^(FIRAuth *a, FIRUser *user) {
                    state.idTokenGeneration += 1;
                }];
            states[key] = state;
        }
    }
    return auth;
}

static FAWState *FAWStateFor(NSString *dartName) {
    NSString *key = (dartName.length == 0 || [dartName isEqualToString:kDartDefaultName])
        ? kDartDefaultName
        : dartName;
    NSMutableDictionary<NSString *, FAWState *> *states = FAWStates();
    @synchronized(states) {
        return states[key];
    }
}

#pragma mark - User serialization

static NSNumber *FAWMillis(NSDate *date) {
    if (date == nil) {
        return nil;
    }
    return @((int64_t)(date.timeIntervalSince1970 * 1000.0));
}

// Serializes one provider entry to the `UserInfo.fromJson` shape.
static NSDictionary *FAWProviderInfoMap(id<FIRUserInfo> info) {
    return @{
        @"uid" : FAWOrNull(info.uid),
        @"email" : FAWOrNull(info.email),
        @"displayName" : FAWOrNull(info.displayName),
        @"photoUrl" : FAWOrNull(info.photoURL.absoluteString),
        @"phoneNumber" : FAWOrNull(info.phoneNumber),
        @"providerId" : FAWOrNull(info.providerID),
        // Provider entries carry no anonymity/verification state of their
        // own; `UserInfo.fromJson` requires the booleans to be present.
        @"isAnonymous" : @NO,
        @"isEmailVerified" : @NO,
    };
}

// Serializes a FIRUser to the `InternalUserInfo` + providerData shape the
// Dart side rebuilds a `UserPlatform` from.
static NSDictionary *FAWUserToMap(FIRUser *user) {
    NSMutableArray *providerData = [NSMutableArray array];
    for (id<FIRUserInfo> info in user.providerData) {
        [providerData addObject:FAWProviderInfoMap(info)];
    }
    return @{
        @"uid" : FAWOrNull(user.uid),
        @"email" : FAWOrNull(user.email),
        @"displayName" : FAWOrNull(user.displayName),
        @"photoUrl" : FAWOrNull(user.photoURL.absoluteString),
        @"phoneNumber" : FAWOrNull(user.phoneNumber),
        @"isAnonymous" : @(user.isAnonymous),
        @"isEmailVerified" : @(user.isEmailVerified),
        @"providerId" : @"firebase",
        @"tenantId" : FAWOrNull(user.tenantID),
        @"refreshToken" : FAWOrNull(user.refreshToken),
        @"creationTimestamp" : FAWOrNull(FAWMillis(user.metadata.creationDate)),
        @"lastSignInTimestamp" : FAWOrNull(FAWMillis(user.metadata.lastSignInDate)),
        @"providerData" : providerData,
    };
}

static NSDictionary *FAWAuthResultToMap(FIRAuthDataResult *result) {
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    map[@"user"] = result.user != nil ? FAWUserToMap(result.user) : [NSNull null];
    FIRAdditionalUserInfo *info = result.additionalUserInfo;
    if (info != nil) {
        NSMutableDictionary *additional = [NSMutableDictionary dictionary];
        additional[@"isNewUser"] = @(info.isNewUser);
        additional[@"providerId"] = FAWOrNull(info.providerID);
        additional[@"username"] = FAWOrNull(info.username);
        if ([NSJSONSerialization isValidJSONObject:info.profile]) {
            additional[@"profile"] = info.profile;
        } else {
            additional[@"profile"] = [NSNull null];
        }
        map[@"additionalUserInfo"] = additional;
    } else {
        map[@"additionalUserInfo"] = [NSNull null];
    }
    return map;
}

#pragma mark - Async operation registry

// Completed operation results, keyed by token. Absence means still pending;
// `firebase_auth_watchos_poll` removes an entry as it returns it.
static NSMutableDictionary<NSNumber *, NSDictionary *> *FAWResults(void) {
    static NSMutableDictionary *results;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ results = [NSMutableDictionary dictionary]; });
    return results;
}

static int64_t FAWNextToken(void) {
    static int64_t next = 1;
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [[NSObject alloc] init]; });
    @synchronized(lock) {
        return next++;
    }
}

static void FAWComplete(int64_t token, NSDictionary *result) {
    NSMutableDictionary *results = FAWResults();
    @synchronized(results) {
        results[@(token)] = result;
    }
}

// Standard completion for operations that resolve to an auth result.
static void (^FAWAuthResultCompletion(int64_t token))(FIRAuthDataResult *, NSError *) {
    return ^(FIRAuthDataResult *result, NSError *error) {
        if (error != nil) {
            FAWComplete(token, FAWErrorDict(error));
        } else {
            FAWComplete(token, FAWAuthResultToMap(result));
        }
    };
}

// Standard completion for operations that resolve to {"ok": true}.
static void (^FAWOkCompletion(int64_t token))(NSError *) {
    return ^(NSError *error) {
        if (error != nil) {
            FAWComplete(token, FAWErrorDict(error));
        } else {
            FAWComplete(token, @{@"ok" : @YES});
        }
    };
}

#pragma mark - Operation dispatch

// Starts the requested operation. Returns NO (with *errorOut set) only for
// synchronous validation failures; asynchronous failures surface via poll.
static BOOL FAWStartOp(NSString *op,
                       NSDictionary *request,
                       FIRAuth *auth,
                       int64_t token,
                       NSDictionary **errorOut) {
    // --- Auth-level operations -------------------------------------------
    if ([op isEqualToString:@"signInAnonymously"]) {
        [auth signInAnonymouslyWithCompletion:FAWAuthResultCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"signInWithEmailAndPassword"]) {
        [auth signInWithEmail:FAWStr(request, @"email") ?: @""
                     password:FAWStr(request, @"password") ?: @""
                   completion:FAWAuthResultCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"createUserWithEmailAndPassword"]) {
        [auth createUserWithEmail:FAWStr(request, @"email") ?: @""
                         password:FAWStr(request, @"password") ?: @""
                       completion:FAWAuthResultCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"signInWithEmailLink"]) {
        [auth signInWithEmail:FAWStr(request, @"email") ?: @""
                         link:FAWStr(request, @"emailLink") ?: @""
                   completion:FAWAuthResultCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"signInWithCustomToken"]) {
        [auth signInWithCustomToken:FAWStr(request, @"token") ?: @""
                         completion:FAWAuthResultCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"sendPasswordResetEmail"]) {
        [auth sendPasswordResetWithEmail:FAWStr(request, @"email") ?: @""
                              completion:FAWOkCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"confirmPasswordReset"]) {
        [auth confirmPasswordResetWithCode:FAWStr(request, @"code") ?: @""
                               newPassword:FAWStr(request, @"newPassword") ?: @""
                                completion:FAWOkCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"verifyPasswordResetCode"]) {
        [auth verifyPasswordResetCode:FAWStr(request, @"code") ?: @""
                           completion:^(NSString *email, NSError *error) {
            if (error != nil) {
                FAWComplete(token, FAWErrorDict(error));
            } else {
                FAWComplete(token, @{@"email" : FAWOrNull(email)});
            }
        }];
        return YES;
    }
    if ([op isEqualToString:@"applyActionCode"]) {
        [auth applyActionCode:FAWStr(request, @"code") ?: @""
                   completion:FAWOkCompletion(token)];
        return YES;
    }

    // --- Current-user operations -----------------------------------------
    FIRUser *user = auth.currentUser;
    if (user == nil) {
        if (errorOut != NULL) {
            *errorOut = FAWSimpleError(@"No user is currently signed in.",
                                       @"no-current-user");
        }
        return NO;
    }
    if ([op isEqualToString:@"reload"]) {
        [user reloadWithCompletion:FAWOkCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"deleteUser"]) {
        [user deleteWithCompletion:FAWOkCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"sendEmailVerification"]) {
        [user sendEmailVerificationWithCompletion:FAWOkCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"verifyBeforeUpdateEmail"]) {
        [user sendEmailVerificationBeforeUpdatingEmail:FAWStr(request, @"newEmail") ?: @""
                                            completion:FAWOkCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"updatePassword"]) {
        [user updatePassword:FAWStr(request, @"password") ?: @""
                  completion:FAWOkCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"updateProfile"]) {
        FIRUserProfileChangeRequest *change = [user profileChangeRequest];
        if ([request[@"hasDisplayName"] boolValue]) {
            change.displayName = FAWStr(request, @"displayName");
        }
        if ([request[@"hasPhotoUrl"] boolValue]) {
            NSString *photoUrl = FAWStr(request, @"photoUrl");
            change.photoURL = photoUrl != nil ? [NSURL URLWithString:photoUrl] : nil;
        }
        [change commitChangesWithCompletion:FAWOkCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"getIdToken"]) {
        BOOL force = [request[@"forceRefresh"] boolValue];
        [user getIDTokenResultForcingRefresh:force
                                  completion:^(FIRAuthTokenResult *result, NSError *error) {
            if (error != nil) {
                FAWComplete(token, FAWErrorDict(error));
                return;
            }
            NSDictionary *claims = result.claims;
            FAWComplete(token, @{
                @"token" : FAWOrNull(result.token),
                @"expirationTimestamp" : FAWOrNull(FAWMillis(result.expirationDate)),
                @"authTimestamp" : FAWOrNull(FAWMillis(result.authDate)),
                @"issuedAtTimestamp" : FAWOrNull(FAWMillis(result.issuedAtDate)),
                @"signInProvider" : FAWOrNull(result.signInProvider),
                @"signInSecondFactor" : FAWOrNull(result.signInSecondFactor),
                @"claims" : [NSJSONSerialization isValidJSONObject:claims]
                    ? claims
                    : (id)[NSNull null],
            });
        }];
        return YES;
    }

    if (errorOut != NULL) {
        *errorOut = FAWSimpleError(
            [NSString stringWithFormat:@"Unsupported auth operation \"%@\" on watchOS.", op],
            @"unimplemented");
    }
    return NO;
}

#pragma mark - Exported FFI

const char *firebase_auth_watchos_begin(const char *request_json) {
    @autoreleasepool {
        if (request_json == NULL) {
            return FAWCopyError(@"Request JSON is null.", @"invalid-argument");
        }
        NSData *data = [@(request_json) dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *request =
            [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![request isKindOfClass:[NSDictionary class]]) {
            return FAWCopyError(@"Request JSON is malformed.", @"invalid-argument");
        }
        NSString *op = FAWStr(request, @"op");
        if (op == nil) {
            return FAWCopyError(@"Request is missing \"op\".", @"invalid-argument");
        }
        NSDictionary *error = nil;
        FIRAuth *auth = FAWAuth(FAWStr(request, @"app") ?: @"", &error);
        if (auth == nil) {
            return FAWCopy(error);
        }
        int64_t token = FAWNextToken();
        if (!FAWStartOp(op, request, auth, token, &error)) {
            return FAWCopy(error);
        }
        return FAWCopy(@{@"token" : @(token)});
    }
}

const char *firebase_auth_watchos_poll(int64_t token) {
    @autoreleasepool {
        NSDictionary *result = nil;
        NSMutableDictionary *results = FAWResults();
        @synchronized(results) {
            result = results[@(token)];
            if (result != nil) {
                [results removeObjectForKey:@(token)];
            }
        }
        return FAWCopy(result ?: @{@"pending" : @YES});
    }
}

const char *firebase_auth_watchos_current_user(const char *app_name) {
    @autoreleasepool {
        NSString *dartName = app_name != NULL ? @(app_name) : @"";
        NSDictionary *error = nil;
        FIRAuth *auth = FAWAuth(dartName, &error);
        if (auth == nil) {
            return FAWCopy(error);
        }
        FAWState *state = FAWStateFor(dartName);
        FIRUser *user = auth.currentUser;
        return FAWCopy(@{
            @"authGeneration" : @(state.authGeneration),
            @"idTokenGeneration" : @(state.idTokenGeneration),
            @"user" : user != nil ? FAWUserToMap(user) : (id)[NSNull null],
        });
    }
}

const char *firebase_auth_watchos_sign_out(const char *app_name) {
    @autoreleasepool {
        NSString *dartName = app_name != NULL ? @(app_name) : @"";
        NSDictionary *error = nil;
        FIRAuth *auth = FAWAuth(dartName, &error);
        if (auth == nil) {
            return FAWCopy(error);
        }
        NSError *signOutError = nil;
        if (![auth signOut:&signOutError]) {
            return FAWCopy(FAWErrorDict(signOutError));
        }
        return FAWCopy(@{@"ok" : @YES});
    }
}

const char *firebase_auth_watchos_set_language_code(const char *app_name,
                                                    const char *code) {
    @autoreleasepool {
        NSString *dartName = app_name != NULL ? @(app_name) : @"";
        NSDictionary *error = nil;
        FIRAuth *auth = FAWAuth(dartName, &error);
        if (auth == nil) {
            return FAWCopy(error);
        }
        NSString *languageCode = code != NULL ? @(code) : @"";
        if (languageCode.length == 0) {
            [auth useAppLanguage];
        } else {
            auth.languageCode = languageCode;
        }
        return FAWCopy(@{@"languageCode" : FAWOrNull(auth.languageCode)});
    }
}

const char *firebase_auth_watchos_use_emulator(const char *app_name,
                                               const char *host,
                                               int64_t port) {
    @autoreleasepool {
        NSString *dartName = app_name != NULL ? @(app_name) : @"";
        NSDictionary *error = nil;
        FIRAuth *auth = FAWAuth(dartName, &error);
        if (auth == nil) {
            return FAWCopy(error);
        }
        [auth useEmulatorWithHost:host != NULL ? @(host) : @"localhost"
                             port:(NSInteger)port];
        return FAWCopy(@{@"ok" : @YES});
    }
}

const char *firebase_auth_watchos_is_sign_in_link(const char *app_name,
                                                  const char *link) {
    @autoreleasepool {
        NSString *dartName = app_name != NULL ? @(app_name) : @"";
        NSDictionary *error = nil;
        FIRAuth *auth = FAWAuth(dartName, &error);
        if (auth == nil) {
            return FAWCopy(error);
        }
        BOOL value = [auth isSignInWithEmailLink:link != NULL ? @(link) : @""];
        return FAWCopy(@{@"value" : @(value)});
    }
}

void firebase_auth_watchos_free(const char *ptr) {
    if (ptr != NULL) {
        free((void *)ptr);
    }
}
