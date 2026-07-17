// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "firebase_storage_watchos_ffi.h"

#import <Foundation/Foundation.h>

@import FirebaseCore;
@import FirebaseStorage;

#include <stdlib.h>

// The Dart-side default app name (`defaultFirebaseAppName`); the Apple SDK
// names its default app "__FIRAPP_DEFAULT".
static NSString *const kDartDefaultName = @"[DEFAULT]";

#pragma mark - JSON helpers

// Serializes a JSON-compatible object to a freshly heap-allocated UTF-8 C
// string. Ownership transfers to the caller (Dart), which releases it with
// `firebase_storage_watchos_free`.
static const char *FSWCopy(id jsonObject) {
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

static id FSWOrNull(id value) {
    return value ?: (id)[NSNull null];
}

// Reads a non-null, non-NSNull string from a decoded JSON map, or nil.
static NSString *FSWStr(NSDictionary *map, NSString *key) {
    id value = map[key];
    if (value == nil || value == (id)[NSNull null] || ![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    return value;
}

static NSDictionary *FSWSimpleError(NSString *message, NSString *code) {
    return @{@"error" : message ?: @"unknown", @"code" : code ?: @"unknown"};
}

static const char *FSWCopyError(NSString *message, NSString *code) {
    return FSWCopy(FSWSimpleError(message, code));
}

#pragma mark - Errors

// Maps a FIRStorageErrorDomain NSError to the FlutterFire string code. The
// SDK's raw codes are stable; matching on them avoids depending on the ObjC
// visibility of the Swift-rewritten error enum.
static NSString *FSWErrorCode(NSError *error) {
    switch (error.code) {
        case -13000: return @"unknown";
        case -13010: return @"object-not-found";
        case -13011: return @"bucket-not-found";
        case -13012: return @"project-not-found";
        case -13013: return @"quota-exceeded";
        case -13020: return @"unauthenticated";
        case -13021: return @"unauthorized";
        case -13030: return @"retry-limit-exceeded";
        case -13031: return @"invalid-checksum";
        case -13032: return @"download-size-exceeded";
        case -13040: return @"canceled";
        case -13050: return @"invalid-argument";
        default: return @"unknown";
    }
}

static NSDictionary *FSWErrorDict(NSError *error) {
    return @{
        @"error" : error.localizedDescription ?: @"unknown",
        @"code" : FSWErrorCode(error),
    };
}

#pragma mark - Storage / reference lookup

// Resolves the FIRStorage instance for a Dart app name + bucket, or nil with
// `*errorOut` set if the app is not configured.
static FIRStorage *FSWStorage(NSDictionary *request, NSDictionary **errorOut) {
    NSString *dartName = FSWStr(request, @"app") ?: @"";
    BOOL isDefault = dartName.length == 0 || [dartName isEqualToString:kDartDefaultName];
    FIRApp *app = isDefault ? [FIRApp defaultApp] : [FIRApp appNamed:dartName];
    if (app == nil) {
        if (errorOut != NULL) {
            *errorOut = FSWSimpleError(
                @"No Firebase App has been created - call Firebase.initializeApp()",
                @"no-app");
        }
        return nil;
    }
    NSString *bucket = FSWStr(request, @"bucket");
    if (bucket.length > 0) {
        return [FIRStorage storageForApp:app
                                     URL:[@"gs://" stringByAppendingString:bucket]];
    }
    return [FIRStorage storageForApp:app];
}

static FIRStorageReference *FSWRef(NSDictionary *request, NSDictionary **errorOut) {
    FIRStorage *storage = FSWStorage(request, errorOut);
    if (storage == nil) {
        return nil;
    }
    return [storage referenceWithPath:FSWStr(request, @"path") ?: @""];
}

#pragma mark - Metadata serialization

// Serializes a FIRStorageMetadata to the `FullMetadata` map shape.
static NSDictionary *FSWMetadataToMap(FIRStorageMetadata *metadata) {
    if (metadata == nil) {
        return nil;
    }
    NSNumber *created = metadata.timeCreated != nil
        ? @((int64_t)(metadata.timeCreated.timeIntervalSince1970 * 1000.0))
        : nil;
    NSNumber *updated = metadata.updated != nil
        ? @((int64_t)(metadata.updated.timeIntervalSince1970 * 1000.0))
        : nil;
    return @{
        @"bucket" : FSWOrNull(metadata.bucket),
        @"fullPath" : FSWOrNull(metadata.path),
        @"name" : FSWOrNull(metadata.name),
        @"size" : @(metadata.size),
        @"generation" : [NSString stringWithFormat:@"%lld", metadata.generation],
        @"metadataGeneration" :
            [NSString stringWithFormat:@"%lld", metadata.metageneration],
        @"metageneration" :
            [NSString stringWithFormat:@"%lld", metadata.metageneration],
        @"md5Hash" : FSWOrNull(metadata.md5Hash),
        @"cacheControl" : FSWOrNull(metadata.cacheControl),
        @"contentDisposition" : FSWOrNull(metadata.contentDisposition),
        @"contentEncoding" : FSWOrNull(metadata.contentEncoding),
        @"contentLanguage" : FSWOrNull(metadata.contentLanguage),
        @"contentType" : FSWOrNull(metadata.contentType),
        @"customMetadata" : FSWOrNull(metadata.customMetadata),
        @"creationTimeMillis" : FSWOrNull(created),
        @"updatedTimeMillis" : FSWOrNull(updated),
    };
}

// Builds a FIRStorageMetadata from a `SettableMetadata`-shaped JSON map.
static FIRStorageMetadata *FSWMetadataFromMap(NSDictionary *map) {
    FIRStorageMetadata *metadata = [[FIRStorageMetadata alloc] init];
    NSString *cacheControl = FSWStr(map, @"cacheControl");
    if (cacheControl) { metadata.cacheControl = cacheControl; }
    NSString *contentDisposition = FSWStr(map, @"contentDisposition");
    if (contentDisposition) { metadata.contentDisposition = contentDisposition; }
    NSString *contentEncoding = FSWStr(map, @"contentEncoding");
    if (contentEncoding) { metadata.contentEncoding = contentEncoding; }
    NSString *contentLanguage = FSWStr(map, @"contentLanguage");
    if (contentLanguage) { metadata.contentLanguage = contentLanguage; }
    NSString *contentType = FSWStr(map, @"contentType");
    if (contentType) { metadata.contentType = contentType; }
    id custom = map[@"customMetadata"];
    if ([custom isKindOfClass:[NSDictionary class]]) {
        metadata.customMetadata = custom;
    }
    return metadata;
}

#pragma mark - Async operation registry (one-shot ops)

static NSMutableDictionary<NSNumber *, NSDictionary *> *FSWResults(void) {
    static NSMutableDictionary *results;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ results = [NSMutableDictionary dictionary]; });
    return results;
}

static int64_t FSWNextId(void) {
    static int64_t next = 1;
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [[NSObject alloc] init]; });
    @synchronized(lock) {
        return next++;
    }
}

static void FSWComplete(int64_t token, NSDictionary *result) {
    NSMutableDictionary *results = FSWResults();
    @synchronized(results) {
        results[@(token)] = result;
    }
}

static void (^FSWOkCompletion(int64_t token))(NSError *) {
    return ^(NSError *error) {
        if (error != nil) {
            FSWComplete(token, FSWErrorDict(error));
        } else {
            FSWComplete(token, @{@"ok" : @YES});
        }
    };
}

static void (^FSWMetadataCompletion(int64_t token))(FIRStorageMetadata *, NSError *) {
    return ^(FIRStorageMetadata *metadata, NSError *error) {
        if (error != nil) {
            FSWComplete(token, FSWErrorDict(error));
        } else {
            FSWComplete(token, @{@"metadata" : FSWOrNull(FSWMetadataToMap(metadata))});
        }
    };
}

static void (^FSWListCompletion(int64_t token))(FIRStorageListResult *, NSError *) {
    return ^(FIRStorageListResult *result, NSError *error) {
        if (error != nil) {
            FSWComplete(token, FSWErrorDict(error));
            return;
        }
        NSMutableArray *items = [NSMutableArray array];
        for (FIRStorageReference *ref in result.items) {
            [items addObject:ref.fullPath];
        }
        NSMutableArray *prefixes = [NSMutableArray array];
        for (FIRStorageReference *ref in result.prefixes) {
            [prefixes addObject:ref.fullPath];
        }
        FSWComplete(token, @{
            @"items" : items,
            @"prefixes" : prefixes,
            @"nextPageToken" : FSWOrNull(result.pageToken),
        });
    };
}

#pragma mark - Task registry (uploads/downloads)

// Latest snapshot per running task, updated from the SDK's observer
// callbacks; `firebase_storage_watchos_task_snapshot` reads it. The task
// object is retained alongside so pause/resume/cancel can reach it.
@interface FSWTaskEntry : NSObject
@property(nonatomic, strong) FIRStorageObservableTask *task;
@property(nonatomic, strong) NSDictionary *snapshot;
@end

@implementation FSWTaskEntry
@end

static NSMutableDictionary<NSNumber *, FSWTaskEntry *> *FSWTasks(void) {
    static NSMutableDictionary *tasks;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ tasks = [NSMutableDictionary dictionary]; });
    return tasks;
}

static FSWTaskEntry *FSWTaskFor(int64_t taskId) {
    NSMutableDictionary<NSNumber *, FSWTaskEntry *> *tasks = FSWTasks();
    @synchronized(tasks) {
        return tasks[@(taskId)];
    }
}

static void FSWUpdateTask(int64_t taskId,
                          NSString *state,
                          FIRStorageTaskSnapshot *snapshot,
                          NSDictionary *extra) {
    FSWTaskEntry *entry = FSWTaskFor(taskId);
    if (entry == nil) {
        return;
    }
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    map[@"state"] = state;
    map[@"bytesTransferred"] = @(snapshot.progress.completedUnitCount);
    map[@"totalBytes"] = @(snapshot.progress.totalUnitCount);
    [map addEntriesFromDictionary:extra ?: @{}];
    @synchronized(FSWTasks()) {
        entry.snapshot = map;
    }
}

// Attaches the standard status observers that keep the snapshot current.
static void FSWObserve(int64_t taskId, FIRStorageObservableTask *task, BOOL isUpload) {
    [task observeStatus:FIRStorageTaskStatusProgress
                handler:^(FIRStorageTaskSnapshot *snapshot) {
        FSWUpdateTask(taskId, @"running", snapshot, nil);
    }];
    [task observeStatus:FIRStorageTaskStatusPause
                handler:^(FIRStorageTaskSnapshot *snapshot) {
        FSWUpdateTask(taskId, @"paused", snapshot, nil);
    }];
    [task observeStatus:FIRStorageTaskStatusResume
                handler:^(FIRStorageTaskSnapshot *snapshot) {
        FSWUpdateTask(taskId, @"running", snapshot, nil);
    }];
    [task observeStatus:FIRStorageTaskStatusSuccess
                handler:^(FIRStorageTaskSnapshot *snapshot) {
        NSDictionary *extra = isUpload
            ? @{@"metadata" : FSWOrNull(FSWMetadataToMap(snapshot.metadata))}
            : nil;
        FSWUpdateTask(taskId, @"success", snapshot, extra);
    }];
    [task observeStatus:FIRStorageTaskStatusFailure
                handler:^(FIRStorageTaskSnapshot *snapshot) {
        NSError *error = snapshot.error;
        BOOL canceled = error != nil && error.code == -13040;
        FSWUpdateTask(taskId, canceled ? @"canceled" : @"error", snapshot,
                      @{@"error" : error != nil ? FSWErrorDict(error)
                                                : FSWSimpleError(@"unknown", @"unknown")});
    }];
}

#pragma mark - One-shot operation dispatch

static BOOL FSWStartOp(NSString *op,
                       NSDictionary *request,
                       int64_t token,
                       NSDictionary **errorOut) {
    FIRStorageReference *ref = FSWRef(request, errorOut);
    if (ref == nil) {
        return NO;
    }
    if ([op isEqualToString:@"delete"]) {
        [ref deleteWithCompletion:FSWOkCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"getDownloadURL"]) {
        [ref downloadURLWithCompletion:^(NSURL *url, NSError *error) {
            if (error != nil) {
                FSWComplete(token, FSWErrorDict(error));
            } else {
                FSWComplete(token, @{@"url" : FSWOrNull(url.absoluteString)});
            }
        }];
        return YES;
    }
    if ([op isEqualToString:@"getMetadata"]) {
        [ref metadataWithCompletion:FSWMetadataCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"updateMetadata"]) {
        id map = request[@"metadata"];
        if (![map isKindOfClass:[NSDictionary class]]) {
            if (errorOut != NULL) {
                *errorOut = FSWSimpleError(@"updateMetadata requires a metadata map.",
                                           @"invalid-argument");
            }
            return NO;
        }
        [ref updateMetadata:FSWMetadataFromMap(map)
                 completion:FSWMetadataCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"listAll"]) {
        [ref listAllWithCompletion:FSWListCompletion(token)];
        return YES;
    }
    if ([op isEqualToString:@"list"]) {
        int64_t maxResults = [request[@"maxResults"] longLongValue];
        NSString *pageToken = FSWStr(request, @"pageToken");
        if (pageToken != nil) {
            [ref listWithMaxResults:maxResults
                          pageToken:pageToken
                         completion:FSWListCompletion(token)];
        } else {
            [ref listWithMaxResults:maxResults completion:FSWListCompletion(token)];
        }
        return YES;
    }
    if ([op isEqualToString:@"getData"]) {
        int64_t maxSize = [request[@"maxSize"] longLongValue];
        [ref dataWithMaxSize:maxSize completion:^(NSData *data, NSError *error) {
            if (error != nil) {
                FSWComplete(token, FSWErrorDict(error));
            } else {
                FSWComplete(token, @{
                    @"data" : FSWOrNull([data base64EncodedStringWithOptions:0]),
                });
            }
        }];
        return YES;
    }
    if (errorOut != NULL) {
        *errorOut = FSWSimpleError(
            [NSString stringWithFormat:@"Unsupported storage operation \"%@\".", op],
            @"unimplemented");
    }
    return NO;
}

#pragma mark - Exported FFI

const char *firebase_storage_watchos_begin(const char *request_json) {
    @autoreleasepool {
        if (request_json == NULL) {
            return FSWCopyError(@"Request JSON is null.", @"invalid-argument");
        }
        NSData *data = [@(request_json) dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *request =
            [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![request isKindOfClass:[NSDictionary class]]) {
            return FSWCopyError(@"Request JSON is malformed.", @"invalid-argument");
        }
        NSString *op = FSWStr(request, @"op");
        if (op == nil) {
            return FSWCopyError(@"Request is missing \"op\".", @"invalid-argument");
        }
        int64_t token = FSWNextId();
        NSDictionary *error = nil;
        if (!FSWStartOp(op, request, token, &error)) {
            return FSWCopy(error);
        }
        return FSWCopy(@{@"token" : @(token)});
    }
}

const char *firebase_storage_watchos_poll(int64_t token) {
    @autoreleasepool {
        NSDictionary *result = nil;
        NSMutableDictionary *results = FSWResults();
        @synchronized(results) {
            result = results[@(token)];
            if (result != nil) {
                [results removeObjectForKey:@(token)];
            }
        }
        return FSWCopy(result ?: @{@"pending" : @YES});
    }
}

const char *firebase_storage_watchos_task_start(const char *request_json) {
    @autoreleasepool {
        if (request_json == NULL) {
            return FSWCopyError(@"Request JSON is null.", @"invalid-argument");
        }
        NSData *data = [@(request_json) dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *request =
            [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![request isKindOfClass:[NSDictionary class]]) {
            return FSWCopyError(@"Request JSON is malformed.", @"invalid-argument");
        }
        NSDictionary *error = nil;
        FIRStorageReference *ref = FSWRef(request, &error);
        if (ref == nil) {
            return FSWCopy(error);
        }
        NSString *kind = FSWStr(request, @"kind") ?: @"";
        id metadataMap = request[@"metadata"];
        FIRStorageMetadata *metadata =
            [metadataMap isKindOfClass:[NSDictionary class]]
                ? FSWMetadataFromMap(metadataMap)
                : nil;

        FIRStorageObservableTask *task = nil;
        BOOL isUpload = YES;
        if ([kind isEqualToString:@"putData"]) {
            NSString *base64 = FSWStr(request, @"data") ?: @"";
            NSData *bytes =
                [[NSData alloc] initWithBase64EncodedString:base64 options:0];
            if (bytes == nil) {
                return FSWCopyError(@"putData payload is not valid base64.",
                                    @"invalid-argument");
            }
            task = [ref putData:bytes metadata:metadata completion:nil];
        } else if ([kind isEqualToString:@"putFile"]) {
            NSString *filePath = FSWStr(request, @"filePath") ?: @"";
            task = [ref putFile:[NSURL fileURLWithPath:filePath]
                       metadata:metadata
                     completion:nil];
        } else if ([kind isEqualToString:@"writeToFile"]) {
            NSString *filePath = FSWStr(request, @"filePath") ?: @"";
            isUpload = NO;
            task = [ref writeToFile:[NSURL fileURLWithPath:filePath]
                         completion:nil];
        } else {
            return FSWCopyError(
                [NSString stringWithFormat:@"Unsupported task kind \"%@\".", kind],
                @"invalid-argument");
        }

        int64_t taskId = FSWNextId();
        FSWTaskEntry *entry = [[FSWTaskEntry alloc] init];
        entry.task = task;
        entry.snapshot = @{
            @"state" : @"running",
            @"bytesTransferred" : @0,
            @"totalBytes" : @0,
        };
        NSMutableDictionary<NSNumber *, FSWTaskEntry *> *tasks = FSWTasks();
        @synchronized(tasks) {
            tasks[@(taskId)] = entry;
        }
        FSWObserve(taskId, task, isUpload);
        return FSWCopy(@{@"taskId" : @(taskId)});
    }
}

const char *firebase_storage_watchos_task_snapshot(int64_t task_id) {
    @autoreleasepool {
        FSWTaskEntry *entry = FSWTaskFor(task_id);
        if (entry == nil) {
            return FSWCopyError(@"Unknown storage task.", @"invalid-argument");
        }
        NSDictionary *snapshot;
        @synchronized(FSWTasks()) {
            snapshot = entry.snapshot;
        }
        return FSWCopy(snapshot);
    }
}

const char *firebase_storage_watchos_task_control(int64_t task_id,
                                                  const char *action) {
    @autoreleasepool {
        FSWTaskEntry *entry = FSWTaskFor(task_id);
        if (entry == nil) {
            return FSWCopyError(@"Unknown storage task.", @"invalid-argument");
        }
        NSString *name = action != NULL ? @(action) : @"";
        // Pause/resume only exist on uploads/downloads (both are
        // FIRStorageObservableTask subclasses implementing the management
        // protocol); the calls are fire-and-forget in the SDK.
        if ([name isEqualToString:@"pause"]) {
            [(id)entry.task pause];
            return FSWCopy(@{@"value" : @YES});
        }
        if ([name isEqualToString:@"resume"]) {
            [(id)entry.task resume];
            return FSWCopy(@{@"value" : @YES});
        }
        if ([name isEqualToString:@"cancel"]) {
            [(id)entry.task cancel];
            return FSWCopy(@{@"value" : @YES});
        }
        return FSWCopyError(
            [NSString stringWithFormat:@"Unknown task action \"%@\".", name],
            @"invalid-argument");
    }
}

const char *firebase_storage_watchos_configure(const char *request_json) {
    @autoreleasepool {
        if (request_json == NULL) {
            return FSWCopyError(@"Request JSON is null.", @"invalid-argument");
        }
        NSData *data = [@(request_json) dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *request =
            [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![request isKindOfClass:[NSDictionary class]]) {
            return FSWCopyError(@"Request JSON is malformed.", @"invalid-argument");
        }
        NSDictionary *error = nil;
        FIRStorage *storage = FSWStorage(request, &error);
        if (storage == nil) {
            return FSWCopy(error);
        }
        NSString *op = FSWStr(request, @"op") ?: @"";
        if ([op isEqualToString:@"useEmulator"]) {
            [storage useEmulatorWithHost:FSWStr(request, @"host") ?: @"localhost"
                                    port:[request[@"port"] integerValue]];
            return FSWCopy(@{@"ok" : @YES});
        }
        // Retry times arrive in milliseconds; the SDK stores seconds.
        double seconds = [request[@"milliseconds"] doubleValue] / 1000.0;
        if ([op isEqualToString:@"setMaxOperationRetryTime"]) {
            storage.maxOperationRetryTime = seconds;
            return FSWCopy(@{@"ok" : @YES});
        }
        if ([op isEqualToString:@"setMaxUploadRetryTime"]) {
            storage.maxUploadRetryTime = seconds;
            return FSWCopy(@{@"ok" : @YES});
        }
        if ([op isEqualToString:@"setMaxDownloadRetryTime"]) {
            storage.maxDownloadRetryTime = seconds;
            return FSWCopy(@{@"ok" : @YES});
        }
        return FSWCopyError(
            [NSString stringWithFormat:@"Unknown configure op \"%@\".", op],
            @"invalid-argument");
    }
}

void firebase_storage_watchos_free(const char *ptr) {
    if (ptr != NULL) {
        free((void *)ptr);
    }
}
