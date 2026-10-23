## 0.1.2

* **A failed or cancelled purchase reaches `purchaseStream`, and the stream
  no longer goes silent after one.** Native code wrote the error's
  `canceled` flag as a boxed C comparison, which is an `int`, so it reached
  Dart as `1` or `0` rather than `true` or `false`, and Dart's `as bool?`
  threw a `TypeError` in the drain timer. Every failed transaction and every
  failed restore, cancelled or not, was lost that way, together with the
  rest of the updates drained with it. In an app that listens from the root
  zone, as Flutter apps usually do, the throw also stopped the timer for
  good: `purchaseStream` delivered nothing more until every listener had
  cancelled and one listened again, which for an app that listens once
  meant until it was restarted. The fix, by
  [@iamoguzhanarslantas](https://github.com/iamoguzhanarslantas) in
  [#4](https://github.com/flutterwatch/plugins/pull/4), boxes the flag as a
  `BOOL`, which reaches JSON as `true` or `false`.
* **Failures that 0.1.1 left unfinished now arrive.** 0.1.1 never delivered
  them, so the app never completed them, and StoreKit delivers an unfinished
  transaction again at each launch, once the app reads `purchaseStream`: on
  0.1.1 a single cancel could silence `purchaseStream` at every launch.
  After the update, each one reaches `purchaseStream` as an `error` or
  `canceled` update with `pendingCompletePurchase` set, at each launch until
  the app completes it, as `in_app_purchase` asks for every such update. An
  app that tells the user about each failed purchase will tell them about
  these too.
* A `canceled` flag of `1` or `0` is read as `true` or `false`, so a native
  build from 0.1.1's sources still reports a cancel as one.
* One malformed update can no longer stop the stream. It is left out and
  reported through `FlutterError.reportError`, and the rest of its batch and
  later batches still arrive. A drain that fails is reported too, and the
  next one runs.
* `SKErrorOverlayCancelled` (code 15) is a cancel, as in
  `in_app_purchase_storekit`.
* The C header says that `canceled` is a JSON boolean.
* Host tests replay the `{"canceled":1}` that 0.1.1 sent and the
  `{"canceled":true}` sent now, listening from the root zone as an app does,
  and check that later batches still arrive after a failed update, a
  malformed one and a drain that throws. They do not reach the native code,
  so the `BOOL` flag and code 15 are not covered by them. The cancel and
  failure flows have not been run end to end yet, on a watch or on the
  Simulator: StoreKit testing starts only when Xcode launches the app,
  which `flutter-watchos drive` does not, so no automated test here can make
  StoreKit fail or cancel a transaction.

## 0.1.1

* **The watchOS implementation stays in place under `flutter-watchos test -d`.**
  `registerWith` takes over `in_app_purchase`'s own platform selection, which
  needs the binding, and it retried only on the next twenty event-loop turns.
  `flutter-watchos test -d` starts a test's `main()` seconds after the plugin
  registrant, so those retries ran out, the test's first `InAppPurchase` call
  installed StoreKit's method-channel implementation, and every call failed
  with `channel-error`. After the twenty quick retries it now retries every
  10 ms for up to ten seconds. Apps and `flutter-watchos drive` were not
  affected: their `main()` creates the binding before the quick retries end.
* Example: `registration_test.dart` waits for the takeover to finish before
  it uses the app-facing API, as a test that starts late has to.

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
* `pubspec.yaml`: `repository` points at this package's folder in the plugins
  repo.
* Comments now say what keeps the FFI exports in the app: the CLI force-loads
  the plugin archive, each export is `used` with default visibility, and the
  CLI keeps global symbols through the App Store strip. `ffiSymbols` lists the
  exports.
* README: a "Not supported on watchOS" table; PORTING_REPORT: an "Interface
  coverage" list of every member of `in_app_purchase_platform_interface` 1.4.1
  and the StoreKit addition, audited by hand.
* `pubspec.yaml`: `topics` (watchos, ffi, in-app-purchase, storekit).
* Example: `pubspec.yaml` names `in_app_purchase: ^3.3.1` instead of `any`.
* Example: the calls into the StoreKit addition are guarded with
  `FlutterWatchosPlatform.isIos` instead of `Platform.isIOS`, which is true on
  the watch, where those calls fail; the example no longer starts with an
  unhandled exception from `setDelegate`. The example depends on
  `flutter_watchos: ^0.1.0` and on `shared_preferences_watchos`, which its
  `shared_preferences` store needs on the watch, and a new integration test
  checks that it starts cleanly. The README and PORTING_REPORT list the
  deviations.
* API docs and comments say "release" for handing native memory back.
* README and the example's StoreKit test describe a product's amount in
  plain words.

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
