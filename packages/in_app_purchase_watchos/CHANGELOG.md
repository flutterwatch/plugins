## 0.0.1

* Initial watchOS FFI implementation, started from a `flutter-watchos plugin
  port` scaffold of `in_app_purchase_storekit`.
* `queryProductDetails`: StoreKit product lookup (`SKProductsRequest`) exposed
  over dart:ffi via a start/poll/read/release handle protocol.
* Purchase flow: `buyConsumable` / `buyNonConsumable`, `purchaseStream`,
  `completePurchase`, and `restorePurchases` via an `SKPaymentQueue` transaction
  observer, drained into `purchaseStream` over dart:ffi.
* Upstream `in_app_purchase` example (demo UI + official `integration_test/`)
  ported to watchOS; builds and passes on the watch simulator.
