# package_info_plus_watchos

The watchOS implementation of [`package_info_plus`](https://pub.dev/packages/package_info_plus).

Scaffolded with [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
and finished by hand as an **FFI** implementation over `NSBundle` — see
`PORTING_REPORT.md`.

## Usage

This is a federated plugin implementation. Apps that already depend on
`package_info_plus` and target watchOS only need to add this package as a
dependency, alongside the upstream plugin:

```yaml
dependencies:
  package_info_plus: ^8.0.0
  package_info_plus_watchos: ^0.1.0
```

`PackageInfo.fromPlatform()` then works on the watch — no imports needed
in app code.

## API coverage

| Field | watchOS |
|---|---|
| `appName` | ✅ `CFBundleDisplayName` / `CFBundleName` |
| `packageName` | ✅ `CFBundleIdentifier` |
| `version` | ✅ `CFBundleShortVersionString` |
| `buildNumber` | ✅ `CFBundleVersion` |
| `buildSignature` | — empty (Android-only concept) |
| `installerStore` | — null (no App Store installer-source API on watchOS) |
| `installTime` / `updateTime` | — null (no watchOS API) |

## Example on the watch screen

The package ships the **upstream example app and its official integration
test verbatim**. The upstream UI is phone-designed and does not fit a watch
screen at native density, so the example's runner opts into the
flutter-watchos content scale (`watchos/Runner/Info.plist`):

```xml
<key>FlutterWatchOSContentScale</key>
<real>0.4</real>
```

This lays the app out in a proportionally larger logical space rendered
smaller — same layout, smaller components — without touching the example's
Dart code. With it, the full official integration test passes on the watch
simulator.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
