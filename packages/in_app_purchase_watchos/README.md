# in_app_purchase_watchos

The watchOS implementation of [`in_app_purchase`](https://pub.dev/packages/in_app_purchase),
over **dart:ffi** (StoreKit). Started from a
[`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
scaffold of `in_app_purchase_storekit`; see `PORTING_REPORT.md` for the API map.

## Usage

This is a federated plugin implementation. An app that already uses
`in_app_purchase` and targets watchOS just adds this package alongside it — the
`in_app_purchase` API picks it up automatically on the watch:

```yaml
dependencies:
  in_app_purchase: ^<latest>
  in_app_purchase_watchos: ^0.0.1
```

## Status

🚧 **In progress.** StoreKit purchasing is available on watchOS (from 6.2), but
the StoreKit *UI surfaces* (`SKStoreProductViewController`, the review prompt,
code redemption) do not exist on the watch and are intentionally out of scope.

Implemented:

- ✅ `queryProductDetails` — product lookup via `SKProductsRequest`.

Not yet implemented (fall back to the platform interface's "unimplemented"
error until they land):

- `buyNonConsumable` / `buyConsumable` — the purchase flow (`SKPaymentQueue`).
- `restorePurchases`, the `purchaseStream`, `completePurchase`.

The native StoreKit code is verified against the API; on-device verification
needs an App Store Connect product configuration and a sandbox account.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
