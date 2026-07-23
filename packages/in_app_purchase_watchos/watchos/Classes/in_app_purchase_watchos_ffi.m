// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of in_app_purchase, over dart:ffi.
// First slice: queryProductDetails via StoreKit's SKProductsRequest.

#import "in_app_purchase_watchos_ffi.h"

#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>
#import <os/lock.h>
#import <stdlib.h>
#import <string.h>

// One in-flight (or completed) product query. Retained by `s_queries` until
// `..._query_release`. `SKProductsRequest.delegate` is a weak reference, so
// the map holding this object strongly is what keeps the delegate alive.
@interface FWIAPQuery : NSObject <SKProductsRequestDelegate>
@property(nonatomic, assign) int64_t handle;
@property(nonatomic, strong) SKProductsRequest *request;
@property(nonatomic, assign) BOOL ready;
// strdup'd UTF-8 result JSON, owned here; freed on release. NULL until ready.
@property(nonatomic, assign) char *resultCStr;
@end

// Guards s_queries, s_nextHandle, and every FWIAPQuery's `ready`/`resultCStr`.
static os_unfair_lock s_lock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSNumber *, FWIAPQuery *> *s_queries = nil;
static int64_t s_nextHandle = 1;

@implementation FWIAPQuery

// Serialises [result] and publishes it, under the shared lock. Callbacks
// arrive on a StoreKit-owned queue, so this may run off the calling thread.
- (void)finishWithResult:(NSDictionary *)result {
  NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
  NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
  const char *utf8 = json.UTF8String ?: "{}";
  char *copy = strdup(utf8);
  os_unfair_lock_lock(&s_lock);
  // A release() may have raced ahead of the callback; only publish if we are
  // still tracked, otherwise drop the copy so it doesn't leak.
  if (s_queries[@(self.handle)] == self) {
    if (self.resultCStr) {
      free(self.resultCStr);
    }
    self.resultCStr = copy;
    self.ready = YES;
  } else {
    free(copy);
  }
  os_unfair_lock_unlock(&s_lock);
}

- (void)productsRequest:(SKProductsRequest *)request
     didReceiveResponse:(SKProductsResponse *)response {
  NSMutableArray<NSDictionary *> *products = [NSMutableArray array];
  for (SKProduct *p in response.products) {
    NSNumberFormatter *fmt = [[NSNumberFormatter alloc] init];
    fmt.numberStyle = NSNumberFormatterCurrencyStyle;
    fmt.locale = p.priceLocale;
    NSString *formatted = [fmt stringFromNumber:p.price] ?: @"";
    [products addObject:@{
      @"id" : p.productIdentifier ?: @"",
      @"title" : p.localizedTitle ?: @"",
      @"description" : p.localizedDescription ?: @"",
      @"price" : formatted,
      @"rawPrice" : @(p.price.doubleValue),
      @"currencyCode" : p.priceLocale.currencyCode ?: @"",
      @"currencySymbol" : p.priceLocale.currencySymbol ?: @"",
    }];
  }
  [self finishWithResult:@{
    @"products" : products,
    @"notFound" : response.invalidProductIdentifiers ?: @[],
  }];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
  [self finishWithResult:@{
    @"products" : @[],
    @"notFound" : @[],
    @"error" : @{
      @"code" : [@(error.code) stringValue] ?: @"",
      @"message" : error.localizedDescription ?: @"",
    },
  }];
}

@end

int64_t in_app_purchase_watchos_query_start(const char *ids_json) {
  @autoreleasepool {
    NSString *jsonStr = ids_json ? [NSString stringWithUTF8String:ids_json] : @"[]";
    NSData *jsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
    id parsed = jsonData ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil] : nil;
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    if ([parsed isKindOfClass:[NSArray class]]) {
      for (id item in (NSArray *)parsed) {
        if ([item isKindOfClass:[NSString class]]) {
          [ids addObject:(NSString *)item];
        }
      }
    }

    FWIAPQuery *query = [[FWIAPQuery alloc] init];

    os_unfair_lock_lock(&s_lock);
    if (!s_queries) {
      s_queries = [NSMutableDictionary dictionary];
    }
    int64_t handle = s_nextHandle++;
    query.handle = handle;
    s_queries[@(handle)] = query;
    os_unfair_lock_unlock(&s_lock);

    SKProductsRequest *request =
        [[SKProductsRequest alloc] initWithProductIdentifiers:ids];
    request.delegate = query;
    query.request = request;
    [request start];
    return handle;
  }
}

bool in_app_purchase_watchos_query_ready(int64_t handle) {
  os_unfair_lock_lock(&s_lock);
  FWIAPQuery *query = s_queries[@(handle)];
  // An unknown handle is reported ready so a poller never spins forever;
  // ..._query_result then returns NULL and Dart surfaces an error.
  bool ready = query ? query.ready : true;
  os_unfair_lock_unlock(&s_lock);
  return ready;
}

const char *in_app_purchase_watchos_query_result(int64_t handle) {
  os_unfair_lock_lock(&s_lock);
  FWIAPQuery *query = s_queries[@(handle)];
  const char *result = (query != nil) ? query.resultCStr : NULL;
  os_unfair_lock_unlock(&s_lock);
  return result;
}

void in_app_purchase_watchos_query_release(int64_t handle) {
  os_unfair_lock_lock(&s_lock);
  FWIAPQuery *query = s_queries[@(handle)];
  if (query) {
    if (query.resultCStr) {
      free(query.resultCStr);
      query.resultCStr = NULL;
    }
    [query.request cancel];
    [s_queries removeObjectForKey:@(handle)];
  }
  os_unfair_lock_unlock(&s_lock);
}
