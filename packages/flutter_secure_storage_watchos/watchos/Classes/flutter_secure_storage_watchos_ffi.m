// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Keychain-backed implementation of flutter_secure_storage for watchOS.
// The Keychain (kSecClassGenericPassword) is fully available on watchOS, so
// this behaves like the Apple (darwin) implementation: each secret is a
// generic-password item keyed by (service, account) where the account is the
// Flutter storage key.

#import "flutter_secure_storage_watchos_ffi.h"

#import <Foundation/Foundation.h>
#import <Security/Security.h>

#include <stdlib.h>
#include <string.h>

static NSString* _nsstr(const char* s) {
    return s == NULL ? nil : [NSString stringWithUTF8String:s];
}

static BOOL _nonempty(const char* s) { return s != NULL && s[0] != '\0'; }

// Maps the `accessibility` option name (matching the darwin plugin) to the
// kSecAttrAccessible constant; defaults to WhenUnlocked.
static CFStringRef _accessible(const char* accessibility) {
    NSString* level = _nsstr(accessibility);
    if ([level isEqualToString:@"passcode"]) {
        return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly;
    } else if ([level isEqualToString:@"unlocked_this_device"]) {
        return kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    } else if ([level isEqualToString:@"first_unlock"]) {
        return kSecAttrAccessibleAfterFirstUnlock;
    } else if ([level isEqualToString:@"first_unlock_this_device"]) {
        return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    }
    return kSecAttrAccessibleWhenUnlocked;
}

// Base query shared by every operation: class + service (+ access group).
static NSMutableDictionary* _baseQuery(const char* service,
                                       const char* access_group) {
    NSMutableDictionary* query = [NSMutableDictionary dictionary];
    query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    NSString* svc = _nonempty(service)
        ? _nsstr(service)
        : @"flutter_secure_storage_service";
    query[(__bridge id)kSecAttrService] = svc;
    if (_nonempty(access_group)) {
        query[(__bridge id)kSecAttrAccessGroup] = _nsstr(access_group);
    }
    return query;
}

static char* _copy_cstring(NSString* s) {
    if (s == nil) {
        return NULL;
    }
    const char* utf8 = s.UTF8String;
    if (utf8 == NULL) {
        return NULL;
    }
    return strdup(utf8);
}

int flutter_secure_storage_watchos_write(const char* key, const char* value,
                                         const char* service,
                                         const char* access_group,
                                         const char* accessibility,
                                         bool synchronizable) {
    @autoreleasepool {
        if (!_nonempty(key)) {
            return -1;
        }
        NSData* data =
            [_nsstr(value) dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];

        NSMutableDictionary* query = _baseQuery(service, access_group);
        query[(__bridge id)kSecAttrAccount] = _nsstr(key);

        // Update if present, otherwise add — matching the darwin plugin, so a
        // second write to the same key overwrites rather than erroring.
        NSDictionary* attrs = @{
            (__bridge id)kSecValueData : data,
            (__bridge id)kSecAttrAccessible : (__bridge id)_accessible(accessibility),
        };

        OSStatus status =
            SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
        if (status == errSecSuccess) {
            status = SecItemUpdate((__bridge CFDictionaryRef)query,
                                   (__bridge CFDictionaryRef)attrs);
        } else if (status == errSecItemNotFound) {
            NSMutableDictionary* add = [query mutableCopy];
            [add addEntriesFromDictionary:attrs];
            if (synchronizable) {
                add[(__bridge id)kSecAttrSynchronizable] = (__bridge id)kCFBooleanTrue;
            }
            status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
        }
        return status == errSecSuccess ? 0 : (int)status;
    }
}

char* flutter_secure_storage_watchos_read(const char* key, const char* service,
                                          const char* access_group) {
    @autoreleasepool {
        if (!_nonempty(key)) {
            return NULL;
        }
        NSMutableDictionary* query = _baseQuery(service, access_group);
        query[(__bridge id)kSecAttrAccount] = _nsstr(key);
        query[(__bridge id)kSecReturnData] = (__bridge id)kCFBooleanTrue;
        query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

        CFTypeRef result = NULL;
        OSStatus status =
            SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        if (status != errSecSuccess || result == NULL) {
            return NULL;
        }
        NSData* data = (__bridge_transfer NSData*)result;
        NSString* value = [[NSString alloc] initWithData:data
                                                encoding:NSUTF8StringEncoding];
        return _copy_cstring(value);
    }
}

int flutter_secure_storage_watchos_contains(const char* key,
                                            const char* service,
                                            const char* access_group) {
    @autoreleasepool {
        if (!_nonempty(key)) {
            return 0;
        }
        NSMutableDictionary* query = _baseQuery(service, access_group);
        query[(__bridge id)kSecAttrAccount] = _nsstr(key);
        OSStatus status =
            SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
        return status == errSecSuccess ? 1 : 0;
    }
}

int flutter_secure_storage_watchos_delete(const char* key, const char* service,
                                          const char* access_group) {
    @autoreleasepool {
        if (!_nonempty(key)) {
            return -1;
        }
        NSMutableDictionary* query = _baseQuery(service, access_group);
        query[(__bridge id)kSecAttrAccount] = _nsstr(key);
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
        if (status == errSecSuccess || status == errSecItemNotFound) {
            return 0;
        }
        return (int)status;
    }
}

char* flutter_secure_storage_watchos_read_all(const char* service,
                                              const char* access_group) {
    @autoreleasepool {
        NSMutableDictionary* query = _baseQuery(service, access_group);
        query[(__bridge id)kSecReturnData] = (__bridge id)kCFBooleanTrue;
        query[(__bridge id)kSecReturnAttributes] = (__bridge id)kCFBooleanTrue;
        query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll;

        CFTypeRef result = NULL;
        OSStatus status =
            SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        if (status == errSecItemNotFound) {
            return strdup("{}");
        }
        if (status != errSecSuccess || result == NULL) {
            return NULL;
        }
        NSArray* items = (__bridge_transfer NSArray*)result;
        NSMutableDictionary<NSString*, NSString*>* pairs =
            [NSMutableDictionary dictionary];
        for (NSDictionary* item in items) {
            NSString* account = item[(__bridge id)kSecAttrAccount];
            NSData* data = item[(__bridge id)kSecValueData];
            if (account == nil) {
                continue;
            }
            NSString* value = data == nil
                ? @""
                : [[NSString alloc] initWithData:data
                                        encoding:NSUTF8StringEncoding];
            pairs[account] = value ?: @"";
        }
        NSData* json = [NSJSONSerialization dataWithJSONObject:pairs
                                                       options:0
                                                         error:nil];
        if (json == nil) {
            return NULL;
        }
        NSString* jsonStr = [[NSString alloc] initWithData:json
                                                  encoding:NSUTF8StringEncoding];
        return _copy_cstring(jsonStr);
    }
}

int flutter_secure_storage_watchos_delete_all(const char* service,
                                              const char* access_group) {
    @autoreleasepool {
        NSMutableDictionary* query = _baseQuery(service, access_group);
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
        if (status == errSecSuccess || status == errSecItemNotFound) {
            return 0;
        }
        return (int)status;
    }
}

void flutter_secure_storage_watchos_free(char* ptr) {
    if (ptr != NULL) {
        free(ptr);
    }
}
