// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// WatchConnectivity over dart:ffi, compiled into both the iPhone app and the
// Apple Watch app. See the header for why there is only one implementation.
//
// A single WCSession delegate pushes every inbound payload — message, context,
// or user-info — into a ring buffer under an os_unfair_lock, tagged with the
// tier that delivered it, then signals Dart. Dart drains the buffer; the
// signal never carries the payload itself (header explains why).

#import "flutter_watch_link_ffi.h"

#import <Foundation/Foundation.h>
#import <WatchConnectivity/WatchConnectivity.h>
#import <os/lock.h>

#include <stdlib.h>
#include <string.h>

// The one WCSession dictionary key this package occupies. Mirrored in
// lib/src/codec.dart. Versioned so a future wire change is detectable rather
// than silently misparsed.
static NSString* const kReservedPayloadKey = @"_fwl_v1";

// Ring-buffer depth. Sized for a burst that accumulated while the app was
// backgrounded, not for indefinite buffering: a companion app that cares about
// durability uses the user-info tier, and one that cares about catching up
// uses the context tier, so dropping the oldest live payloads under pressure
// loses nothing that is not recoverable from the snapshot.
#define FWL_INBOUND_CAPACITY 64

#pragma mark - Dart signalling

static os_unfair_lock _bufferLock = OS_UNFAIR_LOCK_INIT;
static fwl_signal_callback _callback = NULL;

// Wakes Dart. Called from delegate queues, so the callback pointer is read
// under the lock — but invoked *outside* it, because the Dart end is free to
// call straight back into this file and would otherwise deadlock.
static void _signal(int64_t kind) {
    os_unfair_lock_lock(&_bufferLock);
    fwl_signal_callback callback = _callback;
    os_unfair_lock_unlock(&_bufferLock);
    if (callback != NULL) {
        callback(kind);
    }
}

void flutter_watch_link_set_callback(fwl_signal_callback callback) {
    os_unfair_lock_lock(&_bufferLock);
    _callback = callback;
    os_unfair_lock_unlock(&_bufferLock);
}

#pragma mark - Inbound ring buffer

static char* _inbound[FWL_INBOUND_CAPACITY];
static int _head = 0;   // Index of the oldest entry.
static int _count = 0;  // Entries currently buffered.
static int _dropped = 0;

// Takes ownership of `json`.
static void _enqueue(char* json) {
    if (json == NULL) {
        return;
    }
    os_unfair_lock_lock(&_bufferLock);
    if (_count == FWL_INBOUND_CAPACITY) {
        // Full: overwrite the oldest. Newest-wins keeps the buffer holding the
        // most recent state, which is what a converging sync wants.
        free(_inbound[_head]);
        _head = (_head + 1) % FWL_INBOUND_CAPACITY;
        _count--;
        _dropped++;
    }
    _inbound[(_head + _count) % FWL_INBOUND_CAPACITY] = json;
    _count++;
    os_unfair_lock_unlock(&_bufferLock);
    _signal(FWL_SIGNAL_INBOUND);
}

// Most recent asynchronous failure, owned by this file until Dart takes it.
//
// `sendMessage` hands the message to the system and returns; the failure
// arrives on a callback afterwards. Latching it here is what lets Dart find
// out at all — see `..._take_last_error`.
static char* _lastError = NULL;

static void _setLastError(NSString* message) {
    char* copy = strdup(message.UTF8String);
    os_unfair_lock_lock(&_bufferLock);
    free(_lastError);
    _lastError = copy;
    os_unfair_lock_unlock(&_bufferLock);
    _signal(FWL_SIGNAL_ERROR);
}

static char* _dequeue(void) {
    os_unfair_lock_lock(&_bufferLock);
    char* result = NULL;
    if (_count > 0) {
        result = _inbound[_head];
        _inbound[_head] = NULL;
        _head = (_head + 1) % FWL_INBOUND_CAPACITY;
        _count--;
    }
    os_unfair_lock_unlock(&_bufferLock);
    return result;
}

#pragma mark - JSON helpers

// Serializes `object` to a heap-allocated UTF-8 C string the caller owns.
static char* _copyJSON(id object) {
    if (object == nil || ![NSJSONSerialization isValidJSONObject:object]) {
        return NULL;
    }
    NSData* data = [NSJSONSerialization dataWithJSONObject:object
                                                  options:0
                                                    error:nil];
    if (data == nil) {
        return NULL;
    }
    NSString* string = [[NSString alloc] initWithData:data
                                             encoding:NSUTF8StringEncoding];
    return string == nil ? NULL : strdup(string.UTF8String);
}

// Parses a JSON object string, or nil if it is not a JSON object.
static NSDictionary* _parseObject(const char* json) {
    if (json == NULL) {
        return nil;
    }
    NSData* data = [[NSString stringWithUTF8String:json]
        dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        return nil;
    }
    id parsed = [NSJSONSerialization JSONObjectWithData:data
                                                options:0
                                                  error:nil];
    return [parsed isKindOfClass:[NSDictionary class]] ? parsed : nil;
}

// Recovers the sender's payload from a received WCSession dictionary.
//
// Normally that is the JSON string under the reserved key. A dictionary
// without it did not come from this package — a native counterpart app, or an
// older wire version — so rather than dropping it, fall back to treating the
// dictionary itself as the payload when it happens to be JSON-encodable.
static NSDictionary* _payloadObject(NSDictionary<NSString*, id>* received) {
    id reserved = received[kReservedPayloadKey];
    if ([reserved isKindOfClass:[NSString class]]) {
        return _parseObject([reserved UTF8String]);
    }
    return [NSJSONSerialization isValidJSONObject:received] ? received : nil;
}

// Wraps a validated payload for transport.
static NSDictionary* _wrap(NSDictionary* payload) {
    NSData* data = [NSJSONSerialization dataWithJSONObject:payload
                                                  options:0
                                                    error:nil];
    NSString* json = [[NSString alloc] initWithData:data
                                           encoding:NSUTF8StringEncoding];
    return @{kReservedPayloadKey : json};
}

// Buffers an inbound payload as `{"tier": ..., "payload": {...}}`.
static void _receive(NSString* tier, NSDictionary<NSString*, id>* received) {
    NSDictionary* payload = _payloadObject(received);
    if (payload == nil) {
        return;
    }
    _enqueue(_copyJSON(@{@"tier" : tier, @"payload" : payload}));
}

#pragma mark - Pending replies

// Reply blocks for received messages, held until Dart answers.
//
// WCSession hands the receiver a one-shot block and expects it called; there is
// nowhere to store it on the Dart side, so it lives here behind an integer id
// that travels with the message.
static NSMutableDictionary<NSNumber*, void (^)(NSDictionary<NSString*, id>*)>*
    _pendingReplies = nil;
static int64_t _nextReplyId = 1;

// Buffers a message that expects a reply, keeping the block until
// `..._respond` or the timeout.
static void _receiveExpectingReply(
    NSDictionary<NSString*, id>* received,
    void (^replyHandler)(NSDictionary<NSString*, id>*)) {
    NSDictionary* payload = _payloadObject(received);
    if (payload == nil) {
        // Nothing Dart can act on, but the sender is still waiting.
        replyHandler(@{});
        return;
    }

    os_unfair_lock_lock(&_bufferLock);
    if (_pendingReplies == nil) {
        _pendingReplies = [NSMutableDictionary dictionary];
    }
    int64_t replyId = _nextReplyId++;
    _pendingReplies[@(replyId)] = [replyHandler copy];
    os_unfair_lock_unlock(&_bufferLock);

    // A Dart app that never answers must not leave the sender hanging, so the
    // block is answered emptily and dropped after a bounded wait.
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(FWL_REPLY_TIMEOUT_SECONDS * NSEC_PER_SEC)),
        dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
          os_unfair_lock_lock(&_bufferLock);
          void (^pending)(NSDictionary<NSString*, id>*) =
              _pendingReplies[@(replyId)];
          [_pendingReplies removeObjectForKey:@(replyId)];
          os_unfair_lock_unlock(&_bufferLock);
          if (pending != nil) {
              NSLog(@"[flutter_watch_link] no reply within %ds; "
                    @"answering empty",
                    FWL_REPLY_TIMEOUT_SECONDS);
              pending(@{});
          }
        });

    _enqueue(_copyJSON(@{
        @"tier" : @"message",
        @"payload" : payload,
        @"replyId" : @(replyId),
    }));
}

int flutter_watch_link_respond(int64_t reply_id, const char* json) {
    @autoreleasepool {
        NSDictionary* payload = _parseObject(json);
        if (payload == nil) {
            return FWL_INVALID_PAYLOAD;
        }
        os_unfair_lock_lock(&_bufferLock);
        void (^pending)(NSDictionary<NSString*, id>*) =
            _pendingReplies[@(reply_id)];
        [_pendingReplies removeObjectForKey:@(reply_id)];
        os_unfair_lock_unlock(&_bufferLock);
        if (pending == nil) {
            // Unknown or already answered — normally the timeout won the race.
            return FWL_INVALID_PAYLOAD;
        }
        pending(_wrap(payload));
        return FWL_OK;
    }
}

#pragma mark - Session delegate

@interface FWLSessionDelegate : NSObject <WCSessionDelegate>
@end

@implementation FWLSessionDelegate

- (void)session:(WCSession*)session
    activationDidCompleteWithState:(WCSessionActivationState)activationState
                             error:(NSError*)error {
    // State is read on demand from the session itself, so there is nothing to
    // cache — but Dart has to be told to re-read it, or a session that
    // activates after the app's first frame looks permanently inactive.
    if (error != nil) {
        _setLastError([NSString stringWithFormat:@"activate: %@",
                                                 error.localizedDescription]);
    }
    _signal(FWL_SIGNAL_STATE);
}

- (void)sessionReachabilityDidChange:(WCSession*)session {
    _signal(FWL_SIGNAL_STATE);
}

#if !TARGET_OS_WATCH
// Required on iOS only: the phone's session is torn down and handed to a new
// watch when the user switches devices. Reactivating is what keeps the session
// usable afterwards instead of silently dead.
- (void)sessionDidBecomeInactive:(WCSession*)session {
    _signal(FWL_SIGNAL_STATE);
}

- (void)sessionDidDeactivate:(WCSession*)session {
    [session activateSession];
    _signal(FWL_SIGNAL_STATE);
}

- (void)sessionWatchStateDidChange:(WCSession*)session {
    _signal(FWL_SIGNAL_STATE);
}
#endif

- (void)session:(WCSession*)session
    didReceiveMessage:(NSDictionary<NSString*, id>*)message {
    @autoreleasepool {
        _receive(@"message", message);
    }
}

- (void)session:(WCSession*)session
    didReceiveMessage:(NSDictionary<NSString*, id>*)message
         replyHandler:(void (^)(NSDictionary<NSString*, id>*))replyHandler {
    @autoreleasepool {
        // The block is held until Dart answers through `..._respond`, or until
        // the timeout answers for it.
        _receiveExpectingReply(message, replyHandler);
    }
}

- (void)session:(WCSession*)session didReceiveFile:(WCSessionFile*)file {
    @autoreleasepool {
        // The system deletes its copy as soon as this method returns, so the
        // file has to be moved somewhere durable *now* — handing Dart the
        // original URL would hand it a path that is already gone.
        NSFileManager* fm = [NSFileManager defaultManager];
        NSURL* documents = [[fm URLsForDirectory:NSDocumentDirectory
                                       inDomains:NSUserDomainMask] firstObject];
        if (documents == nil) {
            _setLastError(@"didReceiveFile: no documents directory");
            return;
        }
        NSURL* inbox = [documents URLByAppendingPathComponent:@"fwl_inbox"
                                                  isDirectory:YES];
        [fm createDirectoryAtURL:inbox
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:nil];
        // Prefixed with a UUID so two transfers of the same filename cannot
        // overwrite each other before the app has read the first.
        NSString* name = [NSString
            stringWithFormat:@"%@-%@", [[NSUUID UUID] UUIDString],
                             file.fileURL.lastPathComponent ?: @"file"];
        NSURL* destination = [inbox URLByAppendingPathComponent:name];

        NSError* error = nil;
        if (![fm copyItemAtURL:file.fileURL toURL:destination error:&error]) {
            _setLastError([NSString
                stringWithFormat:@"didReceiveFile: %@",
                                 error.localizedDescription]);
            return;
        }

        // Unwraps the JSON string the sender put under the reserved key. A
        // dictionary without it came from something other than this package,
        // and _payloadObject falls back to the dictionary itself.
        NSDictionary* metadata =
            file.metadata == nil ? nil : _payloadObject(file.metadata);
        if (metadata == nil) {
            metadata = @{};
        }
        _enqueue(_copyJSON(@{
            @"tier" : @"file",
            @"path" : destination.path,
            @"metadata" : metadata,
        }));
    }
}

- (void)session:(WCSession*)session
    didReceiveApplicationContext:(NSDictionary<NSString*, id>*)context {
    @autoreleasepool {
        _receive(@"applicationContext", context);
    }
}

- (void)session:(WCSession*)session
    didReceiveUserInfo:(NSDictionary<NSString*, id>*)userInfo {
    @autoreleasepool {
        _receive(@"userInfo", userInfo);
    }
}

@end

#pragma mark - Session access

static FWLSessionDelegate* _delegate = nil;

// The activated session, or nil if activation has not completed.
//
// Returning nil rather than the session itself is what makes every send
// report FWL_NOT_ACTIVATED instead of throwing inside WCSession.
static WCSession* _session(void) {
    if (![WCSession isSupported]) {
        return nil;
    }
    WCSession* session = [WCSession defaultSession];
    return session.activationState == WCSessionActivationStateActivated
               ? session
               : nil;
}

void flutter_watch_link_activate(void) {
    if (![WCSession isSupported]) {
        return;
    }
    // The delegate must be installed before activation, and both are one-shot.
    // Hopped to the main queue because WCSession delivers delegate callbacks
    // relative to the run loop it was activated on; the FFI entry point runs
    // on the Flutter UI thread (plugins/AUTHORING.md §2c).
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            // `_delegate` is a file-static strong reference on purpose:
            // WCSession holds its delegate weakly, so anything less would be
            // deallocated immediately and every callback lost.
            _delegate = [[FWLSessionDelegate alloc] init];
            WCSession* session = [WCSession defaultSession];
            session.delegate = _delegate;
            // Spelled `activateSession` in Objective-C; the Swift importer
            // renames it to `activate()`.
            [session activateSession];
        });
    });
}

int flutter_watch_link_is_supported(void) {
    return [WCSession isSupported] ? 1 : 0;
}

int flutter_watch_link_state(void) {
    @autoreleasepool {
        if (![WCSession isSupported]) {
            return 0;
        }
        WCSession* session = [WCSession defaultSession];
        int state = 0;
        if (session.activationState == WCSessionActivationStateActivated) {
            state |= FWL_BIT_ACTIVATED;
        }
        if (session.reachable) {
            state |= FWL_BIT_REACHABLE;
        }
#if TARGET_OS_WATCH
        // watchOS has no `isPaired`: a watch running this code is by
        // definition paired to an iPhone, so the answer is always yes. What
        // varies is whether the phone app is installed.
        state |= FWL_BIT_COUNTERPART_PAIRED;
        if (session.isCompanionAppInstalled) {
            state |= FWL_BIT_COUNTERPART_INSTALLED;
        }
#else
        // The phone answers both questions separately, and the difference is
        // worth keeping: no watch paired means "pair a watch", while paired
        // without the app means "install it".
        if (session.isPaired) {
            state |= FWL_BIT_COUNTERPART_PAIRED;
        }
        if (session.isWatchAppInstalled) {
            state |= FWL_BIT_COUNTERPART_INSTALLED;
        }
#endif
        return state;
    }
}

#pragma mark - Sending

int flutter_watch_link_send_message(const char* json) {
    @autoreleasepool {
        NSDictionary* payload = _parseObject(json);
        if (payload == nil) {
            return FWL_INVALID_PAYLOAD;
        }
        WCSession* session = _session();
        if (session == nil) {
            return FWL_NOT_ACTIVATED;
        }
        if (!session.reachable) {
            // WCSession queues nothing here, so say so rather than pretending.
            return FWL_NOT_REACHABLE;
        }
        [session sendMessage:_wrap(payload)
                replyHandler:nil
                errorHandler:^(NSError* error) {
                  // Asynchronous, and long after this function returned OK —
                  // latch it so Dart can find out the message never landed.
                  NSLog(@"[flutter_watch_link] sendMessage failed: %@",
                        error.localizedDescription);
                  _setLastError([NSString
                      stringWithFormat:@"sendMessage: %@",
                                       error.localizedDescription]);
                }];
        return FWL_OK;
    }
}

int flutter_watch_link_send_message_with_reply(
    const char* json, int64_t correlation_id) {
    @autoreleasepool {
        NSDictionary* payload = _parseObject(json);
        if (payload == nil) {
            return FWL_INVALID_PAYLOAD;
        }
        WCSession* session = _session();
        if (session == nil) {
            return FWL_NOT_ACTIVATED;
        }
        if (!session.reachable) {
            // A reply is only possible while the counterpart app is running.
            return FWL_NOT_REACHABLE;
        }
        [session sendMessage:_wrap(payload)
            replyHandler:^(NSDictionary<NSString*, id>* reply) {
              NSDictionary* decoded = _payloadObject(reply);
              _enqueue(_copyJSON(@{
                  @"tier" : @"reply",
                  @"correlationId" : @(correlation_id),
                  @"payload" : decoded ?: @{},
              }));
            }
            errorHandler:^(NSError* error) {
              // Routed to the waiting future rather than the errors stream:
              // this failure belongs to one specific call.
              _enqueue(_copyJSON(@{
                  @"tier" : @"replyError",
                  @"correlationId" : @(correlation_id),
                  @"error" : error.localizedDescription ?: @"unknown error",
              }));
            }];
        return FWL_OK;
    }
}

int flutter_watch_link_transfer_file(const char* path,
                                               const char* metadata_json) {
    @autoreleasepool {
        if (path == NULL) {
            return FWL_INVALID_PAYLOAD;
        }
        NSString* filePath = [NSString stringWithUTF8String:path];
        if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            return FWL_INVALID_PAYLOAD;
        }
        // Metadata is optional; an absent or unparseable value is treated as
        // empty rather than failing the transfer.
        //
        // Wrapped like every other tier rather than handed over as a decoded
        // dictionary. WCSession accepts only property-list values in metadata,
        // and a JSON null decodes to NSNull, which is not one — passing it
        // through raises NSInvalidArgumentException. Wrapping also keeps
        // metadata out of the plist numeric coercion that would turn an int
        // into a double on the way across.
        NSDictionary* parsed =
            metadata_json == NULL ? nil : _parseObject(metadata_json);
        NSDictionary* metadata = parsed == nil ? nil : _wrap(parsed);
        WCSession* session = _session();
        if (session == nil) {
            return FWL_NOT_ACTIVATED;
        }
        [session transferFile:[NSURL fileURLWithPath:filePath]
                     metadata:metadata];
        return FWL_OK;
    }
}

int flutter_watch_link_outstanding_file_transfer_count(void) {
    @autoreleasepool {
        if (![WCSession isSupported]) {
            return 0;
        }
        return (int)[WCSession defaultSession].outstandingFileTransfers.count;
    }
}

int flutter_watch_link_update_application_context(const char* json) {
    @autoreleasepool {
        NSDictionary* payload = _parseObject(json);
        if (payload == nil) {
            return FWL_INVALID_PAYLOAD;
        }
        WCSession* session = _session();
        if (session == nil) {
            return FWL_NOT_ACTIVATED;
        }
        NSError* error = nil;
        [session updateApplicationContext:_wrap(payload) error:&error];
        if (error != nil) {
            NSLog(@"[flutter_watch_link] updateApplicationContext "
                  @"failed: %@",
                  error.localizedDescription);
            return FWL_NATIVE_ERROR;
        }
        return FWL_OK;
    }
}

int flutter_watch_link_transfer_user_info(const char* json) {
    @autoreleasepool {
        NSDictionary* payload = _parseObject(json);
        if (payload == nil) {
            return FWL_INVALID_PAYLOAD;
        }
        WCSession* session = _session();
        if (session == nil) {
            return FWL_NOT_ACTIVATED;
        }
        [session transferUserInfo:_wrap(payload)];
        return FWL_OK;
    }
}

#pragma mark - Reading

char* flutter_watch_link_application_context(void) {
    @autoreleasepool {
        if (![WCSession isSupported]) {
            return NULL;
        }
        NSDictionary* received =
            [WCSession defaultSession].receivedApplicationContext;
        if (received.count == 0) {
            return NULL;
        }
        return _copyJSON(_payloadObject(received));
    }
}

char* flutter_watch_link_sent_application_context(void) {
    @autoreleasepool {
        if (![WCSession isSupported]) {
            return NULL;
        }
        NSDictionary* sent = [WCSession defaultSession].applicationContext;
        if (sent.count == 0) {
            return NULL;
        }
        return _copyJSON(_payloadObject(sent));
    }
}

char* flutter_watch_link_poll_inbound(void) {
    return _dequeue();
}

int flutter_watch_link_outstanding_transfer_count(void) {
    @autoreleasepool {
        if (![WCSession isSupported]) {
            return 0;
        }
        return (int)[WCSession defaultSession].outstandingUserInfoTransfers.count;
    }
}

int flutter_watch_link_dropped_inbound_count(void) {
    os_unfair_lock_lock(&_bufferLock);
    int dropped = _dropped;
    os_unfair_lock_unlock(&_bufferLock);
    return dropped;
}

char* flutter_watch_link_take_last_error(void) {
    os_unfair_lock_lock(&_bufferLock);
    char* error = _lastError;
    _lastError = NULL;  // Ownership transfers to the caller.
    os_unfair_lock_unlock(&_bufferLock);
    return error;
}

void flutter_watch_link_free(char* value) {
    free(value);
}
