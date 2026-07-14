# shared_preferences_watchos

The watchOS implementation of [`shared_preferences`](https://pub.dev/packages/shared_preferences).

Scaffolded with [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
and finished by hand as an **FFI** implementation over `NSUserDefaults` —
see `PORTING_REPORT.md`.

## Usage

```yaml
dependencies:
  shared_preferences: ^2.3.0
  shared_preferences_watchos: ^0.1.0
```

Both the classic `SharedPreferences` API and the newer
`SharedPreferencesAsync` API work on the watch — no imports needed in app
code.

## How it works

The store is a single JSON object persisted in `NSUserDefaults` under one
private key. The native side only loads and saves that blob; all typing and
filtering is done in Dart, so the five supported value types (`bool`, `int`,
`double`, `String`, `List<String>`) round-trip exactly. Both the legacy
`SharedPreferencesStorePlatform` and the async `SharedPreferencesAsyncPlatform`
are registered against the same store, mirroring `shared_preferences_foundation`.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
