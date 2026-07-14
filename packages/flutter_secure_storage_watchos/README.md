# flutter_secure_storage_watchos

The watchOS implementation of [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage).

Secrets are stored in the watch **Keychain** (`kSecClassGenericPassword`),
reached over dart:ffi. The Keychain is fully available on watchOS, so this
behaves like the Apple (iOS/macOS) implementation.

> Scaffolded by [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
> from `flutter_secure_storage_darwin`, then implemented and verified by hand.

## Usage

This is a federated plugin implementation. Apps that already depend on
`flutter_secure_storage` and target watchOS only need to add this package
alongside it:

```yaml
dependencies:
  flutter_secure_storage: ^<latest>
  flutter_secure_storage_watchos: ^0.0.1
```

The plugin registers automatically via Flutter's federated registry — no
explicit imports required from app code.

## Behaviour on watchOS

- `write`, `read`, `containsKey`, `delete`, `readAll`, `deleteAll` are all
  supported, keyed by the `accountName` option (Keychain service).
- The `accessibility` and `synchronizable` options are honoured; `groupId`
  (access group) requires the keychain-access-groups entitlement.
- Biometric-gated items are not offered: the watch has no Face ID / Touch ID.

## Status

| Platform | Implemented |
|----------|-------------|
| Apple Watch (`watchos`) | yes |
| Watch simulator (`watchsimulator`) | yes |

The Keychain round-trip (read / write / delete / readAll / containsKey) is
verified by the host-side unit tests and the unified demo on the watch
simulator. The example ships flutter_secure_storage's own upstream
`integration_test/app_test.dart` verbatim; it is a phone-shaped page-object
sweep (tapping a floating action button to add list rows, driving popup menus)
whose widgets a ~200 px watch screen never materialises, so most of its cases
cannot be driven on the watch — a viewport limitation of that test, not of the
Keychain implementation.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
