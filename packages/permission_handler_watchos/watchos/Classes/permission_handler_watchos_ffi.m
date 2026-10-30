// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
//
// The FFI surface, the answers kept for Dart, and the table of strategies.
// See the header for the contract.

#import "permission_handler_watchos_ffi.h"
#import "phw_internal.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <os/lock.h>
#import <stdlib.h>
#import <string.h>

static os_unfair_lock _lock = OS_UNFAIR_LOCK_INIT;
static phw_signal_callback _callback = NULL;
static NSMutableDictionary<NSNumber*, NSDictionary*>* _results = nil;
// Requests that were answered, so a second answer to one is dropped.
static NSMutableSet<NSNumber*>* _answered = nil;
static int64_t _nextRequest = 1;

// ---- Shared helpers ---------------------------------------------------------

Class phw_class(NSString* framework, NSString* className) {
    Class cls = NSClassFromString(className);
    if (cls == nil) {
        NSString* path = [NSString
            stringWithFormat:@"/System/Library/Frameworks/%@.framework/%@", framework,
                             framework];
        dlopen(path.fileSystemRepresentation, RTLD_LAZY);
        cls = NSClassFromString(className);
    }
    return cls;
}

BOOL phw_has_key(NSString* key) {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:key] != nil;
}

void phw_missing_key(NSString* key, PHWErrorHandler failed) {
    failed(@"MISSING_USAGE_DESCRIPTION",
           [NSString stringWithFormat:@"The app's Info.plist has no %@, which the system "
                                      @"prompt for this permission needs.",
                                      key]);
}

NSInteger phw_class_integer(Class cls, SEL selector) {
    return ((NSInteger (*)(Class, SEL))objc_msgSend)(cls, selector);
}

NSInteger phw_class_integer_with(Class cls, SEL selector, NSInteger argument) {
    return ((NSInteger (*)(Class, SEL, NSInteger))objc_msgSend)(cls, selector, argument);
}

BOOL phw_class_bool(Class cls, SEL selector) {
    return ((BOOL (*)(Class, SEL))objc_msgSend)(cls, selector);
}

// ---- Answers ----------------------------------------------------------------

static char* _json(id object) {
    NSData* data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (data == nil) {
        return NULL;
    }
    char* out = malloc(data.length + 1);
    if (out == NULL) {
        return NULL;
    }
    memcpy(out, data.bytes, data.length);
    out[data.length] = '\0';
    return out;
}

static int64_t _newRequest(void) {
    os_unfair_lock_lock(&_lock);
    int64_t request = _nextRequest++;
    os_unfair_lock_unlock(&_lock);
    return request;
}

static void _answer(int64_t request, NSDictionary* answer) {
    os_unfair_lock_lock(&_lock);
    if (_results == nil) {
        _results = [NSMutableDictionary dictionary];
        _answered = [NSMutableSet set];
    }
    BOOL first = ![_answered containsObject:@(request)];
    if (first) {
        [_answered addObject:@(request)];
        _results[@(request)] = answer;
    }
    phw_signal_callback callback = _callback;
    os_unfair_lock_unlock(&_lock);
    if (first && callback != NULL) {
        callback(PHW_SIGNAL_RESULT);
    }
}

static PHWErrorHandler _failer(int64_t request) {
    return ^(NSString* code, NSString* message) {
        _answer(request, @{@"error" : @{@"code" : code, @"message" : message}});
    };
}

// ---- Strategies -------------------------------------------------------------

// Main queue only. A group the build left out answers through
// PHWUnknownStrategy: its file's function says which (phw_internal.h).
static id<PHWStrategy> _strategy(int32_t permission) {
    static NSMutableDictionary<NSString*, id<PHWStrategy>>* strategies;
    if (strategies == nil) {
        strategies = [NSMutableDictionary dictionary];
    }
    Class kind;
    switch ((PHWPermission)permission) {
        case PHWPermissionNotification:
            kind = [PHWNotificationStrategy class];
            break;
        case PHWPermissionLocation:
        case PHWPermissionLocationAlways:
        case PHWPermissionLocationWhenInUse:
            kind = phw_location_strategy((PHWPermission)permission);
            break;
        case PHWPermissionSensors:
            kind = phw_motion_strategy();
            break;
        case PHWPermissionMicrophone:
            kind = phw_microphone_strategy();
            break;
        case PHWPermissionContacts:
            kind = phw_contacts_strategy();
            break;
        case PHWPermissionCalendar:
        case PHWPermissionCalendarWriteOnly:
        case PHWPermissionCalendarFullAccess:
        case PHWPermissionReminders:
            kind = phw_events_strategy((PHWPermission)permission);
            break;
        case PHWPermissionBluetooth:
            kind = phw_bluetooth_strategy();
            break;
        case PHWPermissionStorage:
            kind = [PHWStorageStrategy class];
            break;
        case PHWPermissionCriticalAlerts:
            kind = [PHWCriticalAlertsStrategy class];
            break;
        case PHWPermissionAssistant:
            kind = phw_assistant_strategy();
            break;
        default:
            kind = [PHWUnknownStrategy class];
            break;
    }
    NSString* name = NSStringFromClass(kind);
    id<PHWStrategy> strategy = strategies[name];
    if (strategy == nil) {
        strategy = [[kind alloc] init];
        strategies[name] = strategy;
    }
    return strategy;
}

@implementation PHWUnknownStrategy

- (void)checkPermission:(PHWPermission)permission done:(PHWStatusHandler)done {
    done(PHWStatusDenied);
}

- (void)checkService:(PHWPermission)permission
                done:(PHWServiceHandler)done
              failed:(PHWErrorHandler)failed {
    done(PHWServiceDisabled);
}

- (void)requestPermission:(PHWPermission)permission
                     done:(PHWStatusHandler)done
                   failed:(PHWErrorHandler)failed {
    done(PHWStatusPermanentlyDenied);
}

@end

@implementation PHWStorageStrategy

- (void)checkPermission:(PHWPermission)permission done:(PHWStatusHandler)done {
    done(PHWStatusGranted);
}

- (void)checkService:(PHWPermission)permission
                done:(PHWServiceHandler)done
              failed:(PHWErrorHandler)failed {
    done(PHWServiceNotApplicable);
}

- (void)requestPermission:(PHWPermission)permission
                     done:(PHWStatusHandler)done
                   failed:(PHWErrorHandler)failed {
    done(PHWStatusGranted);
}

@end

// ---- FFI --------------------------------------------------------------------

void permission_handler_watchos_set_callback(phw_signal_callback callback) {
    os_unfair_lock_lock(&_lock);
    _callback = callback;
    os_unfair_lock_unlock(&_lock);
}

int64_t permission_handler_watchos_check(int32_t permission) {
    int64_t request = _newRequest();
    dispatch_async(dispatch_get_main_queue(), ^{
        [_strategy(permission) checkPermission:(PHWPermission)permission
                                          done:^(PHWStatus status) {
            _answer(request, @{@"status" : @(status)});
        }];
    });
    return request;
}

int64_t permission_handler_watchos_service(int32_t permission) {
    int64_t request = _newRequest();
    dispatch_async(dispatch_get_main_queue(), ^{
        [_strategy(permission) checkService:(PHWPermission)permission
            done:^(PHWService service) {
                _answer(request, @{@"service" : @(service)});
            }
            failed:_failer(request)];
    });
    return request;
}

int64_t permission_handler_watchos_request(int32_t permission) {
    int64_t request = _newRequest();
    dispatch_async(dispatch_get_main_queue(), ^{
        [_strategy(permission) requestPermission:(PHWPermission)permission
            done:^(PHWStatus status) {
                _answer(request, @{@"status" : @(status)});
            }
            failed:_failer(request)];
    });
    return request;
}

char* permission_handler_watchos_take_result(int64_t request) {
    os_unfair_lock_lock(&_lock);
    NSDictionary* result = _results[@(request)];
    [_results removeObjectForKey:@(request)];
    [_answered removeObject:@(request)];
    os_unfair_lock_unlock(&_lock);
    return result == nil ? NULL : _json(result);
}

void permission_handler_watchos_release(char* string) {
    free(string);
}
