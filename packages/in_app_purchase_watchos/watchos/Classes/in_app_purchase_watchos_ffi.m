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

// Guards all shared state below.
static os_unfair_lock s_lock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSNumber *, FWIAPQuery *> *s_queries = nil;
static int64_t s_nextHandle = 1;

// SKProducts cached from every successful query, so buy() can build a payment
// from a product id (StoreKit requires the SKProduct, not just its id). Keyed
// by productIdentifier.
static NSMutableDictionary<NSString *, SKProduct *> *s_products = nil;
// Transaction updates from the payment observer, awaiting drain by Dart.
static NSMutableArray<NSDictionary *> *s_updates = nil;
// Transactions we may still need to finish, keyed by the purchaseID reported to
// Dart (transactionIdentifier, or a synthesized id for failed ones).
static NSMutableDictionary<NSString *, SKPaymentTransaction *> *s_transactions = nil;
// Last strdup'd drain result; freed and replaced on each drain.
static char *s_drainBuffer = NULL;

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
  // Cache the SKProducts so a later buy() can build a payment from an id.
  os_unfair_lock_lock(&s_lock);
  if (!s_products) {
    s_products = [NSMutableDictionary dictionary];
  }
  for (SKProduct *p in response.products) {
    if (p.productIdentifier) {
      s_products[p.productIdentifier] = p;
    }
  }
  os_unfair_lock_unlock(&s_lock);

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

#pragma mark - Availability

bool in_app_purchase_watchos_can_make_payments(void) {
  return [SKPaymentQueue canMakePayments];
}

#pragma mark - Purchase flow

static NSString *FWIAPStatusName(SKPaymentTransactionState state) {
  switch (state) {
    case SKPaymentTransactionStatePurchasing:
      return @"purchasing";
    case SKPaymentTransactionStatePurchased:
      return @"purchased";
    case SKPaymentTransactionStateFailed:
      return @"failed";
    case SKPaymentTransactionStateRestored:
      return @"restored";
    case SKPaymentTransactionStateDeferred:
      return @"deferred";
  }
  return @"purchasing";
}

// The app's App Store receipt, base64-encoded, or "" when absent (e.g. an
// unsigned build or a Simulator with no StoreKit test session).
static NSString *FWIAPReceiptBase64(void) {
  NSURL *url = [[NSBundle mainBundle] appStoreReceiptURL];
  if (!url) {
    return @"";
  }
  NSData *data = [NSData dataWithContentsOfURL:url];
  return data ? [data base64EncodedStringWithOptions:0] : @"";
}

// Builds one transaction-update dict. Pure (no shared-state access) so it can
// run outside the lock — the receipt read is file I/O we don't want to hold it
// across.
static NSDictionary *FWIAPBuildUpdate(SKPaymentTransaction *txn) {
  // StoreKit has no transactionIdentifier until a transaction is final. Report
  // it empty rather than inventing one, so an app keyed on purchaseID does not
  // see two different ids for the same purchase; only final states need an id,
  // and those get a synthesised one below purely so finish() has a key.
  const BOOL isFinal = txn.transactionState == SKPaymentTransactionStatePurchased ||
                       txn.transactionState == SKPaymentTransactionStateFailed ||
                       txn.transactionState == SKPaymentTransactionStateRestored;
  NSString *purchaseID = txn.transactionIdentifier
                             ?: (isFinal ? [NSUUID UUID].UUIDString : @"");
  NSMutableDictionary *update = [NSMutableDictionary dictionary];
  update[@"productID"] = txn.payment.productIdentifier ?: @"";
  update[@"purchaseID"] = purchaseID;
  update[@"status"] = FWIAPStatusName(txn.transactionState);
  if (txn.transactionDate) {
    long long ms = (long long)(txn.transactionDate.timeIntervalSince1970 * 1000.0);
    update[@"transactionDate"] = [@(ms) stringValue];
  }
  update[@"receipt"] = FWIAPReceiptBase64();
  if (txn.transactionState == SKPaymentTransactionStateFailed && txn.error) {
    update[@"error"] = @{
      @"code" : [@(txn.error.code) stringValue],
      @"message" : txn.error.localizedDescription ?: @"",
      @"canceled" : @(txn.error.code == SKErrorPaymentCancelled),
    };
  }
  return update;
}

@interface FWIAPPaymentObserver : NSObject <SKPaymentTransactionObserver>
@end

@implementation FWIAPPaymentObserver

- (void)paymentQueue:(SKPaymentQueue *)queue
    updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
  // Build updates (incl. receipt I/O) outside the lock, then publish together.
  NSMutableArray<NSDictionary *> *built = [NSMutableArray array];
  NSMutableDictionary<NSString *, SKPaymentTransaction *> *finishable =
      [NSMutableDictionary dictionary];
  for (SKPaymentTransaction *txn in transactions) {
    NSDictionary *update = FWIAPBuildUpdate(txn);
    [built addObject:update];
    switch (txn.transactionState) {
      case SKPaymentTransactionStatePurchased:
      case SKPaymentTransactionStateFailed:
      case SKPaymentTransactionStateRestored:
        finishable[update[@"purchaseID"]] = txn;  // Dart finishes via completePurchase.
        break;
      default:
        break;  // purchasing / deferred are not final.
    }
  }

  os_unfair_lock_lock(&s_lock);
  if (!s_updates) {
    s_updates = [NSMutableArray array];
  }
  if (!s_transactions) {
    s_transactions = [NSMutableDictionary dictionary];
  }
  [s_updates addObjectsFromArray:built];
  [s_transactions addEntriesFromDictionary:finishable];
  os_unfair_lock_unlock(&s_lock);
}

// A failed restore produces no transactions at all, so without this the caller
// would wait forever on a stream that never emits. Publish a synthetic update
// (empty productID, no purchaseID to finish) carrying the error.
- (void)paymentQueue:(SKPaymentQueue *)queue
    restoreCompletedTransactionsFailedWithError:(NSError *)error {
  NSDictionary *update = @{
    @"productID" : @"",
    @"purchaseID" : @"",
    @"status" : @"failed",
    @"receipt" : @"",
    @"error" : @{
      @"code" : [@(error.code) stringValue],
      @"message" : error.localizedDescription ?: @"",
      @"canceled" : @(error.code == SKErrorPaymentCancelled),
    },
  };
  os_unfair_lock_lock(&s_lock);
  if (!s_updates) {
    s_updates = [NSMutableArray array];
  }
  [s_updates addObject:update];
  os_unfair_lock_unlock(&s_lock);
}

@end

static FWIAPPaymentObserver *s_observer = nil;

void in_app_purchase_watchos_purchases_start(void) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    s_observer = [[FWIAPPaymentObserver alloc] init];
    [[SKPaymentQueue defaultQueue] addTransactionObserver:s_observer];
  });
}

bool in_app_purchase_watchos_buy(const char *product_id,
                                 const char *application_username,
                                 int32_t quantity) {
  @autoreleasepool {
    if (!product_id) {
      return false;
    }
    NSString *pid = [NSString stringWithUTF8String:product_id];
    os_unfair_lock_lock(&s_lock);
    SKProduct *product = s_products[pid];
    os_unfair_lock_unlock(&s_lock);
    if (!product) {
      return false;  // Not queried yet — the caller must query first.
    }
    SKMutablePayment *payment = [SKMutablePayment paymentWithProduct:product];
    if (quantity > 1) {
      payment.quantity = quantity;
    }
    if (application_username && strlen(application_username) > 0) {
      payment.applicationUsername = [NSString stringWithUTF8String:application_username];
    }
    [[SKPaymentQueue defaultQueue] addPayment:payment];
    return true;
  }
}

const char *in_app_purchase_watchos_purchases_drain(void) {
  @autoreleasepool {
    os_unfair_lock_lock(&s_lock);
    NSArray *updates = s_updates ? [s_updates copy] : @[];
    [s_updates removeAllObjects];
    NSData *data = [NSJSONSerialization dataWithJSONObject:updates options:0 error:nil];
    NSString *json =
        data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"[]";
    if (s_drainBuffer) {
      free(s_drainBuffer);
    }
    s_drainBuffer = strdup(json.UTF8String ?: "[]");
    const char *result = s_drainBuffer;
    os_unfair_lock_unlock(&s_lock);
    return result;
  }
}

void in_app_purchase_watchos_finish(const char *purchase_id) {
  @autoreleasepool {
    if (!purchase_id) {
      return;
    }
    NSString *pid = [NSString stringWithUTF8String:purchase_id];
    os_unfair_lock_lock(&s_lock);
    SKPaymentTransaction *txn = s_transactions[pid];
    if (txn) {
      [s_transactions removeObjectForKey:pid];
    }
    os_unfair_lock_unlock(&s_lock);
    if (txn) {
      [[SKPaymentQueue defaultQueue] finishTransaction:txn];
    }
  }
}

void in_app_purchase_watchos_restore(const char *application_username) {
  @autoreleasepool {
    if (application_username && strlen(application_username) > 0) {
      [[SKPaymentQueue defaultQueue]
          restoreCompletedTransactionsWithApplicationUsername:
              [NSString stringWithUTF8String:application_username]];
    } else {
      [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
    }
  }
}
