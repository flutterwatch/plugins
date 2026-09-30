# shared_preferences_watchos

The watchOS implementation of [`shared_preferences`](https://pub.dev/packages/shared_preferences).

Scaffolded with [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
and finished by hand as an **FFI** implementation over `NSUserDefaults` —
see `PORTING_REPORT.md`.

## Usage

`shared_preferences` does not include a watchOS implementation, so add
this package alongside it:

```yaml
dependencies:
  shared_preferences: ^2.5.5
  shared_preferences_watchos: ^0.1.1
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

## Not supported on watchOS

These members of `shared_preferences_platform_interface` 2.4.2 throw or fail on watchOS.
`PORTING_REPORT.md` lists every member under "Interface coverage".

| Member | On watchOS | Why |
|---|---|---|
| `clearWithPrefix` / `getAllWithPrefix` | fail with `UnimplementedError` | deprecated in the interface; `shared_preferences` 2.3 and later calls `clearWithParameters` and `getAllWithParameters` |

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
