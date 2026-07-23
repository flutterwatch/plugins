## 0.0.1

* Initial watchOS FFI implementation, started from a `flutter-watchos plugin
  port` scaffold of `in_app_purchase_storekit`.
* `queryProductDetails`: StoreKit product lookup (`SKProductsRequest`) exposed
  over dart:ffi via a start/poll/read/release handle protocol.
