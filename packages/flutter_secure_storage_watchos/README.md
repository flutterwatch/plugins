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
  flutter_secure_storage: ^11.2.0
  flutter_secure_storage_watchos: ^0.1.0
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
simulator. The example ships the example app and
`integration_test/app_test.dart` of `flutter_secure_storage` 11.2.0 verbatim,
matching the example's `flutter_secure_storage: ^11.2.0`. The test is a
page-object sweep of the phone demo (adding list rows with a floating action
button, driving popup menus) plus direct Keychain cases. As upstream intends,
its Android cases skip off Android, and its iOS-device cases skip when the
`SIMULATOR_DEVICE_NAME` environment variable is set. `PORTING_REPORT.md`
records each run on the watch and the cases that do not pass there, with the
reason.

## Example on the watch screen

The package ships the **upstream example app and its official integration
test verbatim**, both from `flutter_secure_storage` 11.2.0. The upstream UI
is phone-designed and does not fit a watch screen at native density, so the
example's runner opts into the flutter-watchos content scale
(`watchos/Runner/Info.plist`):

```xml
<key>FlutterWatchOSContentScale</key>
<real>0.4</real>
```

This lays the app out in a proportionally larger logical space rendered
smaller — same layout, smaller components — without touching the example's
Dart code.

## Not supported on watchOS

These members of `flutter_secure_storage_platform_interface` 2.1.1 throw or fail on watchOS.
`PORTING_REPORT.md` lists every member under "Interface coverage".

| Member | On watchOS | Why |
|---|---|---|
| `checkUpgradeStatus` | returns `SecureStorageUpgradeStatus.unsupported` | the interface default; there is no earlier watchOS storage format to check |

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
