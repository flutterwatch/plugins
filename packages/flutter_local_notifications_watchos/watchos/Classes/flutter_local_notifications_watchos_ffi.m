// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Local notifications for watchOS. See the header for the contract.
//
// Each notification this package adds carries its id, its payload and its
// presentation flags in `userInfo`, under keys of its own; a callback for a
// notification without them belongs to someone else (a push, another
// plugin) and is left alone.

#import "flutter_local_notifications_watchos_ffi.h"

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import <os/lock.h>
#import <stdlib.h>
#import <string.h>

static NSString* const kIdKey = @"dev.flutterwatch.flnw.id";
static NSString* const kPayloadKey = @"dev.flutterwatch.flnw.payload";
static NSString* const kPresentKey = @"dev.flutterwatch.flnw.present";

// Posted by the flutter-watchos host's application delegate.
static NSString* const kWillPresent = @"FlutterWatchOSNotificationWillPresent";
static NSString* const kDidReceiveResponse =
    @"FlutterWatchOSNotificationDidReceiveResponse";

// How many taps wait for Dart before the oldest is dropped.
static const NSUInteger kResponseBuffer = 64;

static os_unfair_lock _lock = OS_UNFAIR_LOCK_INIT;
static flnw_signal_callback _callback = NULL;
static BOOL _initialized = NO;
// Set once Dart has asked for the launch tap: a tap after that is no longer
// the answer it got, so it queues for the response callback instead.
static BOOL _launchRead = NO;
static NSDictionary* _launch = nil;
static NSMutableArray<NSDictionary*>* _responses = nil;
static NSDictionary* _defaults = nil;
static NSMutableDictionary<NSNumber*, id>* _results = nil;
static int64_t _nextRequest = 1;

static void _signal(int64_t kind) {
    os_unfair_lock_lock(&_lock);
    flnw_signal_callback callback = _callback;
    os_unfair_lock_unlock(&_lock);
    if (callback != NULL) {
        callback(kind);
    }
}

static char* _json(id object) {
    if (object == nil) {
        return NULL;
    }
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

static NSDictionary* _parse(const char* json) {
    if (json == NULL) {
        return @{};
    }
    NSData* data = [NSData dataWithBytes:json length:strlen(json)];
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [parsed isKindOfClass:[NSDictionary class]] ? parsed : @{};
}

static int64_t _newRequest(void) {
    os_unfair_lock_lock(&_lock);
    int64_t request = _nextRequest++;
    os_unfair_lock_unlock(&_lock);
    return request;
}

static void _finish(int64_t request, id result) {
    os_unfair_lock_lock(&_lock);
    if (_results == nil) {
        _results = [NSMutableDictionary dictionary];
    }
    _results[@(request)] = result;
    os_unfair_lock_unlock(&_lock);
    _signal(FLNW_SIGNAL_REQUEST);
}

static void _fail(int64_t request, NSString* code, NSError* error) {
    _finish(request, @{
        @"error" : @{
            @"code" : code,
            @"message" : error.localizedDescription ?: @"",
        }
    });
}

static BOOL _flag(NSDictionary* dict, NSString* key) {
    id value = dict[key];
    return [value isKindOfClass:[NSNumber class]] && [value boolValue];
}

// A presentation flag: the notification's own when it set one, the
// initialization default otherwise, and on when neither did.
static BOOL _present(NSDictionary* own, NSString* key) {
    id value = own[key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value boolValue];
    }
    os_unfair_lock_lock(&_lock);
    id fallback = _defaults[key];
    os_unfair_lock_unlock(&_lock);
    return [fallback isKindOfClass:[NSNumber class]] ? [fallback boolValue] : YES;
}

static UNAuthorizationOptions _authorizationOptions(NSDictionary* request) {
    UNAuthorizationOptions options = 0;
    if (_flag(request, @"alert")) {
        options |= UNAuthorizationOptionAlert;
    }
    if (_flag(request, @"sound")) {
        options |= UNAuthorizationOptionSound;
    }
    if (_flag(request, @"badge")) {
        options |= UNAuthorizationOptionBadge;
    }
    if (_flag(request, @"provisional")) {
        options |= UNAuthorizationOptionProvisional;
    }
    if (_flag(request, @"critical")) {
        options |= UNAuthorizationOptionCriticalAlert;
    }
    return options;
}

static void _requestAuthorization(int64_t request, UNAuthorizationOptions options) {
    [[UNUserNotificationCenter currentNotificationCenter]
        requestAuthorizationWithOptions:options
                      completionHandler:^(BOOL granted, NSError* error) {
        if (error != nil) {
            _fail(request, @"permission", error);
            return;
        }
        _finish(request, @{@"granted" : @(granted)});
    }];
}

// ---- Callbacks from the host's notification-center delegate ---------------

static void _onWillPresent(NSNotification* note) {
    NSDictionary* payload = note.userInfo[@"payload"];
    NSMutableDictionary* options = note.userInfo[@"options"];
    if (![payload isKindOfClass:[NSDictionary class]] || payload[kIdKey] == nil ||
        ![options isKindOfClass:[NSMutableDictionary class]]) {
        return;
    }
    id own = payload[kPresentKey];
    NSDictionary* flags = [own isKindOfClass:[NSDictionary class]] ? own : @{};
    BOOL alert = _present(flags, @"presentAlert");
    BOOL banner = [flags[@"presentBanner"] isKindOfClass:[NSNumber class]]
                      ? [flags[@"presentBanner"] boolValue]
                      : alert && _present(flags, @"presentBanner");
    BOOL list = [flags[@"presentList"] isKindOfClass:[NSNumber class]]
                    ? [flags[@"presentList"] boolValue]
                    : alert && _present(flags, @"presentList");
    UNNotificationPresentationOptions presentation = 0;
    if (banner) {
        presentation |= UNNotificationPresentationOptionBanner;
    }
    if (list) {
        presentation |= UNNotificationPresentationOptionList;
    }
    if (_present(flags, @"presentSound")) {
        presentation |= UNNotificationPresentationOptionSound;
    }
    if (_present(flags, @"presentBadge")) {
        presentation |= UNNotificationPresentationOptionBadge;
    }
    options[@"options"] = @(presentation);
}

static void _onResponse(NSNotification* note) {
    NSDictionary* payload = note.userInfo[@"payload"];
    NSString* action = note.userInfo[@"actionIdentifier"];
    if (![payload isKindOfClass:[NSDictionary class]] || payload[kIdKey] == nil) {
        return;
    }
    BOOL tapped = action == nil ||
                  [action isEqualToString:UNNotificationDefaultActionIdentifier];
    BOOL dismissed = [action isEqualToString:UNNotificationDismissActionIdentifier];
    NSDictionary* response = @{
        @"id" : payload[kIdKey],
        @"actionId" : tapped || dismissed ? [NSNull null] : action,
        @"payload" : payload[kPayloadKey] ?: [NSNull null],
        // NotificationResponseType: selectedNotification,
        // selectedNotificationAction, notificationDismissed.
        @"type" : @(tapped ? 0 : (dismissed ? 2 : 1)),
    };
    os_unfair_lock_lock(&_lock);
    BOOL initialized = _initialized;
    if (!initialized && !_launchRead && _launch == nil) {
        // The tap that launched the app, for getNotificationAppLaunchDetails.
        _launch = response;
    } else {
        // For the response callback: at once when `initialize` has run,
        // otherwise when it does. The host posts the tap from the main thread
        // while Dart runs on its own, so the launch tap can also come in after
        // Dart has read the launch details; it must not be lost then.
        if (_responses == nil) {
            _responses = [NSMutableArray array];
        }
        [_responses addObject:response];
        if (_responses.count > kResponseBuffer) {
            [_responses removeObjectAtIndex:0];
        }
    }
    os_unfair_lock_unlock(&_lock);
    if (initialized) {
        _signal(FLNW_SIGNAL_RESPONSES);
    }
}

// Runs when the binary loads, before the host's delegate can post the tap
// that launched the app, which it does not keep for later.
__attribute__((constructor)) static void _observe(void) {
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:kWillPresent
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification* note) {
        _onWillPresent(note);
    }];
    [center addObserverForName:kDidReceiveResponse
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification* note) {
        _onResponse(note);
    }];
}

// ---- Building requests ------------------------------------------------------

static UNNotificationCategory* _category(NSDictionary* json) {
    NSMutableArray<UNNotificationAction*>* actions = [NSMutableArray array];
    for (NSDictionary* action in json[@"actions"]) {
        if (![action isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        // DarwinNotificationActionOption values match UNNotificationActionOptions.
        UNNotificationActionOptions options =
            (UNNotificationActionOptions)[action[@"options"] unsignedIntegerValue];
        [actions addObject:[UNNotificationAction actionWithIdentifier:action[@"identifier"]
                                                               title:action[@"title"]
                                                             options:options]];
    }
    // DarwinNotificationCategoryOption values match UNNotificationCategoryOptions.
    UNNotificationCategoryOptions options =
        (UNNotificationCategoryOptions)[json[@"options"] unsignedIntegerValue];
    return [UNNotificationCategory categoryWithIdentifier:json[@"identifier"]
                                                  actions:actions
                                        intentIdentifiers:@[]
                                                  options:options];
}

static UNNotificationTrigger* _trigger(NSDictionary* json) {
    NSString* type = json[@"type"];
    if ([type isEqualToString:@"interval"]) {
        return [UNTimeIntervalNotificationTrigger
            triggerWithTimeInterval:MAX(1.0, [json[@"seconds"] doubleValue])
                            repeats:[json[@"repeats"] boolValue]];
    }
    if ([type isEqualToString:@"calendar"]) {
        NSTimeZone* zone = [NSTimeZone timeZoneWithName:json[@"timeZone"] ?: @""]
                               ?: [NSTimeZone localTimeZone];
        NSCalendar* calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
        calendar.timeZone = zone;
        NSDate* date =
            [NSDate dateWithTimeIntervalSince1970:[json[@"epochMs"] doubleValue] / 1000.0];
        id match = json[@"match"];
        NSCalendarUnit time =
            NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
        NSCalendarUnit units = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | time;
        if ([match isKindOfClass:[NSNumber class]]) {
            // DateTimeComponents: time, dayOfWeekAndTime, dayOfMonthAndTime,
            // dateAndTime.
            switch ([match integerValue]) {
                case 0:
                    units = time;
                    break;
                case 1:
                    units = NSCalendarUnitWeekday | time;
                    break;
                case 2:
                    units = NSCalendarUnitDay | time;
                    break;
                default:
                    units = NSCalendarUnitMonth | NSCalendarUnitDay | time;
                    break;
            }
        }
        NSDateComponents* components = [calendar components:units fromDate:date];
        components.calendar = calendar;
        components.timeZone = zone;
        return [UNCalendarNotificationTrigger
            triggerWithDateMatchingComponents:components
                                      repeats:[match isKindOfClass:[NSNumber class]]];
    }
    return nil;
}

static UNMutableNotificationContent* _content(NSDictionary* json, NSError** error) {
    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    id title = json[@"title"];
    id body = json[@"body"];
    if ([title isKindOfClass:[NSString class]]) {
        content.title = title;
    }
    if ([body isKindOfClass:[NSString class]]) {
        content.body = body;
    }
    id raw = json[@"details"];
    NSDictionary* details = [raw isKindOfClass:[NSDictionary class]] ? raw : @{};
    if ([details[@"subtitle"] isKindOfClass:[NSString class]]) {
        content.subtitle = details[@"subtitle"];
    }
    if ([details[@"threadIdentifier"] isKindOfClass:[NSString class]]) {
        content.threadIdentifier = details[@"threadIdentifier"];
    }
    if ([details[@"categoryIdentifier"] isKindOfClass:[NSString class]]) {
        content.categoryIdentifier = details[@"categoryIdentifier"];
    }
    if ([details[@"badgeNumber"] isKindOfClass:[NSNumber class]]) {
        content.badge = details[@"badgeNumber"];
    }
    NSMutableDictionary* present = [NSMutableDictionary dictionary];
    for (NSString* key in @[ @"presentAlert", @"presentSound", @"presentBadge",
                             @"presentBanner", @"presentList" ]) {
        if ([details[key] isKindOfClass:[NSNumber class]]) {
            present[key] = details[key];
        }
    }
    // watchOS plays only the default sound: there is no soundNamed: here.
    if (_present(present, @"presentSound")) {
        content.sound = [UNNotificationSound defaultSound];
    }
    if (@available(watchOS 8.0, *)) {
        id level = details[@"interruptionLevel"];
        if ([level isKindOfClass:[NSNumber class]]) {
            // InterruptionLevel: passive, active, timeSensitive, critical.
            switch ([level integerValue]) {
                case 0:
                    content.interruptionLevel = UNNotificationInterruptionLevelPassive;
                    break;
                case 2:
                    content.interruptionLevel = UNNotificationInterruptionLevelTimeSensitive;
                    break;
                case 3:
                    content.interruptionLevel = UNNotificationInterruptionLevelCritical;
                    break;
                default:
                    content.interruptionLevel = UNNotificationInterruptionLevelActive;
                    break;
            }
        }
    }
    NSMutableArray<UNNotificationAttachment*>* attachments = [NSMutableArray array];
    for (NSDictionary* item in details[@"attachments"]) {
        if (![item isKindOfClass:[NSDictionary class]] ||
            ![item[@"filePath"] isKindOfClass:[NSString class]]) {
            continue;
        }
        NSDictionary* options = _flag(item, @"hideThumbnail")
                                    ? @{UNNotificationAttachmentOptionsThumbnailHiddenKey : @YES}
                                    : nil;
        UNNotificationAttachment* attachment = [UNNotificationAttachment
            attachmentWithIdentifier:[item[@"identifier"] isKindOfClass:[NSString class]]
                                         ? item[@"identifier"]
                                         : @""
                                 URL:[NSURL fileURLWithPath:item[@"filePath"]]
                             options:options
                               error:error];
        if (attachment == nil) {
            return nil;
        }
        [attachments addObject:attachment];
    }
    content.attachments = attachments;
    content.userInfo = @{
        kIdKey : json[@"id"] ?: @0,
        kPayloadKey : [json[@"payload"] isKindOfClass:[NSString class]] ? json[@"payload"] : @"",
        kPresentKey : present,
    };
    return content;
}

static NSDictionary* _describe(UNNotificationRequest* request) {
    NSDictionary* info = request.content.userInfo;
    return @{
        @"id" : info[kIdKey],
        @"title" : request.content.title ?: @"",
        @"body" : request.content.body ?: @"",
        @"payload" : info[kPayloadKey] ?: [NSNull null],
        @"threadIdentifier" : request.content.threadIdentifier ?: @"",
    };
}

// ---- FFI --------------------------------------------------------------------

void flutter_local_notifications_watchos_set_callback(flnw_signal_callback callback) {
    os_unfair_lock_lock(&_lock);
    _callback = callback;
    os_unfair_lock_unlock(&_lock);
}

int64_t flutter_local_notifications_watchos_initialize(const char* json) {
    int64_t request = _newRequest();
    NSDictionary* settings = _parse(json);
    NSMutableSet<UNNotificationCategory*>* categories = [NSMutableSet set];
    for (NSDictionary* category in settings[@"categories"]) {
        if ([category isKindOfClass:[NSDictionary class]] &&
            [category[@"identifier"] isKindOfClass:[NSString class]]) {
            [categories addObject:_category(category)];
        }
    }
    if (categories.count > 0) {
        [[UNUserNotificationCenter currentNotificationCenter]
            setNotificationCategories:categories];
    }
    os_unfair_lock_lock(&_lock);
    id defaults = settings[@"defaults"];
    _defaults = [defaults isKindOfClass:[NSDictionary class]] ? defaults : nil;
    _initialized = YES;
    os_unfair_lock_unlock(&_lock);

    id asked = settings[@"request"];
    UNAuthorizationOptions options =
        _authorizationOptions([asked isKindOfClass:[NSDictionary class]] ? asked : @{});
    if (options == 0) {
        _finish(request, @{@"granted" : @YES});
    } else {
        _requestAuthorization(request, options);
    }
    return request;
}

int64_t flutter_local_notifications_watchos_request_permissions(const char* json) {
    int64_t request = _newRequest();
    _requestAuthorization(request, _authorizationOptions(_parse(json)));
    return request;
}

int64_t flutter_local_notifications_watchos_check_permissions(void) {
    int64_t request = _newRequest();
    [[UNUserNotificationCenter currentNotificationCenter]
        getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* s) {
        BOOL enabled = s.authorizationStatus == UNAuthorizationStatusAuthorized ||
                       s.authorizationStatus == UNAuthorizationStatusProvisional;
        // A comparison is an int in C, so it is cast to BOOL to reach JSON
        // as true or false, not 1 or 0, which Dart would read as false.
        _finish(request, @{
            @"isEnabled" : @(enabled),
            @"isAlertEnabled" : @((BOOL)(s.alertSetting == UNNotificationSettingEnabled)),
            @"isSoundEnabled" : @((BOOL)(s.soundSetting == UNNotificationSettingEnabled)),
            // watchOS shows no badges and has no badge setting.
            @"isBadgeEnabled" : @NO,
            @"isProvisionalEnabled" :
                @((BOOL)(s.authorizationStatus == UNAuthorizationStatusProvisional)),
            @"isCriticalEnabled" :
                @((BOOL)(s.criticalAlertSetting == UNNotificationSettingEnabled)),
        });
    }];
    return request;
}

int64_t flutter_local_notifications_watchos_add(const char* json) {
    int64_t request = _newRequest();
    NSDictionary* notification = _parse(json);
    NSError* error = nil;
    UNMutableNotificationContent* content = _content(notification, &error);
    if (content == nil) {
        _fail(request, @"attachment", error);
        return request;
    }
    id rawTrigger = notification[@"trigger"];
    UNNotificationTrigger* trigger =
        _trigger([rawTrigger isKindOfClass:[NSDictionary class]] ? rawTrigger : @{});
    NSString* identifier = [notification[@"id"] stringValue] ?: @"0";
    UNNotificationRequest* unRequest = [UNNotificationRequest requestWithIdentifier:identifier
                                                                            content:content
                                                                            trigger:trigger];
    [[UNUserNotificationCenter currentNotificationCenter]
        addNotificationRequest:unRequest
         withCompletionHandler:^(NSError* addError) {
        if (addError != nil) {
            _fail(request, @"add", addError);
            return;
        }
        _finish(request, @{});
    }];
    return request;
}

void flutter_local_notifications_watchos_cancel(int64_t notification) {
    NSString* identifier = [NSString stringWithFormat:@"%lld", (long long)notification];
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center removePendingNotificationRequestsWithIdentifiers:@[ identifier ]];
    [center removeDeliveredNotificationsWithIdentifiers:@[ identifier ]];
}

void flutter_local_notifications_watchos_cancel_all(int pending_only) {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center removeAllPendingNotificationRequests];
    if (pending_only == 0) {
        [center removeAllDeliveredNotifications];
    }
}

int64_t flutter_local_notifications_watchos_pending(void) {
    int64_t request = _newRequest();
    [[UNUserNotificationCenter currentNotificationCenter]
        getPendingNotificationRequestsWithCompletionHandler:^(
            NSArray<UNNotificationRequest*>* requests) {
        NSMutableArray<NSDictionary*>* out = [NSMutableArray array];
        for (UNNotificationRequest* r in requests) {
            if (r.content.userInfo[kIdKey] != nil) {
                [out addObject:_describe(r)];
            }
        }
        _finish(request, out);
    }];
    return request;
}

int64_t flutter_local_notifications_watchos_active(void) {
    int64_t request = _newRequest();
    [[UNUserNotificationCenter currentNotificationCenter]
        getDeliveredNotificationsWithCompletionHandler:^(
            NSArray<UNNotification*>* notifications) {
        NSMutableArray<NSDictionary*>* out = [NSMutableArray array];
        for (UNNotification* n in notifications) {
            if (n.request.content.userInfo[kIdKey] != nil) {
                [out addObject:_describe(n.request)];
            }
        }
        _finish(request, out);
    }];
    return request;
}

char* flutter_local_notifications_watchos_launch_details(void) {
    os_unfair_lock_lock(&_lock);
    NSDictionary* launch = _launch;
    _launchRead = YES;
    os_unfair_lock_unlock(&_lock);
    return _json(@{
        @"launched" : @((BOOL)(launch != nil)),
        @"response" : launch ?: [NSNull null],
    });
}

char* flutter_local_notifications_watchos_poll_responses(void) {
    os_unfair_lock_lock(&_lock);
    NSArray<NSDictionary*>* drained = _responses.count == 0 ? nil : [_responses copy];
    [_responses removeAllObjects];
    os_unfair_lock_unlock(&_lock);
    return _json(drained);
}

char* flutter_local_notifications_watchos_take_request_result(int64_t request) {
    os_unfair_lock_lock(&_lock);
    id result = _results[@(request)];
    [_results removeObjectForKey:@(request)];
    os_unfair_lock_unlock(&_lock);
    return _json(result);
}

void flutter_local_notifications_watchos_release(char* string) {
    free(string);
}
