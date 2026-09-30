## 0.1.0

* The platform addition: `InAppPurchase.instance.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>()`
  now returns `InAppPurchaseWatchosPlatformAddition` instead of StoreKit's
  method-channel addition, whose calls failed with `channel-error` on the
  watch. It extends StoreKit's addition, so the upstream cast works. Its five
  methods (`sync`, `presentCodeRedemptionSheet`,
  `refreshPurchaseVerificationData`, `setDelegate`,
  `showPriceConsentIfNeeded`) return a `Future` that fails with an
  `UnsupportedError` naming watchOS; none throws when it is called.
  `registerWith()` installs it on every registration attempt, because
  `in_app_purchase`'s own selection installs StoreKit's addition each time it
  runs.
* Requires `in_app_purchase: ^3.2.3` and `in_app_purchase_storekit: ^0.4.0`,
  the first versions whose StoreKit addition has `sync()`. Analysis and the
  unit tests pass at both lower bounds (`flutter pub downgrade`).
* README: the install snippet names `in_app_purchase: ^3.3.1` and this
  version.

## 0.0.1

* Initial watchOS FFI implementation, started from a `flutter-watchos plugin
  port` scaffold of `in_app_purchase_storekit`.
* Works as a normal federated implementation: apps just add this package and
  use the standard `in_app_purchase` API. `registerWith()` pre-empts the
  app-facing package's `defaultTargetPlatform`-based selection, which would
  otherwise install the iOS method-channel implementation over this one.
* `purchaseStream` only polls StoreKit while it has a listener, and always
  cancels its timer — polling with nobody listening costs watch battery.
* `buyConsumable` asserts `autoConsume`, matching iOS, instead of silently
  ignoring it.
* Losing the registration race is now reported via `debugPrint` rather than
  failing silently later with an opaque `channel-error`.
* `isAvailable`: `SKPaymentQueue canMakePayments` — the first call every app
  makes.
* `queryProductDetails`: StoreKit product lookup (`SKProductsRequest`) exposed
  over dart:ffi via a start/poll/read/release handle protocol.
* Purchase flow: `buyConsumable` / `buyNonConsumable`, `purchaseStream`,
  `completePurchase`, and `restorePurchases` via an `SKPaymentQueue` transaction
  observer, drained into `purchaseStream` over dart:ffi.
* Upstream `in_app_purchase` example (demo UI + official `integration_test/`)
  ported to watchOS; builds and passes on the watch simulator.
