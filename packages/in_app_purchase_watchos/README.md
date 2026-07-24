# in_app_purchase_watchos

The watchOS implementation of [`in_app_purchase`](https://pub.dev/packages/in_app_purchase),
over **dart:ffi** (StoreKit). Started from a
[`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
scaffold of `in_app_purchase_storekit`; see `PORTING_REPORT.md` for the API map.

## Usage

Add this package alongside `in_app_purchase`:

```yaml
dependencies:
  in_app_purchase: ^<latest>
  in_app_purchase_watchos: ^0.0.1
```

### ⚠️ One extra line is required on watchOS

Unlike most federated plugins, this one is **not** picked up automatically. The
app-facing `in_app_purchase` package chooses its implementation from
`defaultTargetPlatform` instead of from the plugin registrant, and watchOS
reports as `TargetPlatform.iOS`. So the first time you touch
`InAppPurchase.instance`, it installs the *iOS StoreKit method-channel*
implementation over this one — and method channels do not exist on watchOS, so
every call then fails with `channel-error`.

Take the platform back once, at startup, before using the API:

```dart
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_watchos/in_app_purchase_watchos.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  InAppPurchase.instance;              // runs the one-time platform selection
  InAppPurchaseWatchos.registerWith(); // ...then take it back on watchOS
  runApp(const MyApp());
}
```

After that the standard `InAppPurchase` API works normally — every method reads
`InAppPurchasePlatform.instance` at call time, and the selection above only ever
runs once, so this sticks. (Verified on device; see
`example/integration_test/registration_test.dart`, which fails loudly if
upstream ever fixes the selection and the workaround becomes unnecessary.)

## Status

🚧 **In progress.** StoreKit purchasing is available on watchOS (from 6.2), but
the StoreKit *UI surfaces* (`SKStoreProductViewController`, the review prompt,
code redemption) do not exist on the watch and are intentionally out of scope.

Implemented:

- ✅ `isAvailable` — `SKPaymentQueue canMakePayments`.
- ✅ `queryProductDetails` — product lookup via `SKProductsRequest`.
- ✅ Purchase flow — `buyConsumable` / `buyNonConsumable`, `purchaseStream`,
  `completePurchase`, `restorePurchases` via `SKPaymentQueue` (a transaction
  observer whose updates are drained into `purchaseStream`).

Out of scope (no watchOS equivalent): the StoreKit UI surfaces
(`SKStoreProductViewController`, the review prompt, code redemption).

The plugin builds, links, and runs on the watch simulator (all FFI symbols
present in the binary; the example's integration test passes). Verifying a
*real* purchase round-trip still needs StoreKit test products (a `.storekit`
configuration) or an App Store Connect sandbox account — the bare Simulator has
no products, so `queryProductDetails` returns "not found" and a buy cannot
complete there.

## Example

`example/` is the upstream `in_app_purchase` example app (its demo UI and
official `integration_test/`), ported to watchOS with a runner via
`flutter-watchos plugin port --include-example`. Run it on a watch simulator:

```sh
cd example
flutter-watchos drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/in_app_purchase_test.dart \
  -d <watch-sim>
```

The demo exercises the full purchasing flow. On a bare Simulator there are no
StoreKit products, so product lookup returns "not found" and a purchase cannot
complete — add a `.storekit` test configuration (or use a sandbox account) to
exercise it end to end.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
