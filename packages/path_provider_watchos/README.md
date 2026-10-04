# path_provider_watchos

The watchOS implementation of [`path_provider`](https://pub.dev/packages/path_provider).

> Scaffolded by [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
> from `path_provider_foundation`, then finished by hand.

## Usage

This is a federated plugin implementation. Apps that already depend on
`path_provider` and target watchOS only need to add this package alongside
it:

```yaml
dependencies:
  path_provider: ^2.1.6
  path_provider_watchos: ^0.1.0
```

The plugin registers automatically via Flutter's federated registry — no
explicit imports required from app code.

## Status

| Platform | Implemented |
|----------|-------------|
| Apple Watch (`watchos`) | yes |
| Watch simulator (`watchsimulator`) | yes |

## Not supported on watchOS

These members of `path_provider_platform_interface` 2.1.3 throw or fail on watchOS.
`PORTING_REPORT.md` lists every member under "Interface coverage".

| Member | On watchOS | Why |
|---|---|---|
| `getDownloadsPath` | throws `UnimplementedError` | watchOS has no Downloads directory |
| `getExternalStoragePath` / `getExternalStoragePaths` / `getExternalCachePaths` | throw `UnimplementedError` | external storage is an Android concept |

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
