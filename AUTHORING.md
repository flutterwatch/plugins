# Authoring a watchOS Plugin

This guide explains the structure of a `*_watchos` federated plugin and
how to finish one by hand.

> **Start with the porter.** Run `flutter-watchos plugin port --from-pub
> <upstream_apple_impl>` first; use this document to understand the
> generated layout and to complete the parts the porter leaves to a human.
> `path_provider_watchos` is the reference implementation to copy from.

## 1. The watchOS plugin model: FFI, not method channels

Method-channel plugins are not supported on watchOS — a package whose
`watchos:` block declares only `pluginClass:` builds, but its channel
calls throw `MissingPluginException` (the CLI warns about this at build
time). A working watchOS plugin therefore ships native code as
**exported C symbols** consumed over `dart:ffi`:

1. **Native** — `watchos/Classes/<name>_watchos_ffi.{h,m}` exporting
   functions marked `__attribute__((visibility("default"))) used`.
   Objective-C is fine (the CLI compiles `.m/.mm/.c` with `-fobjc-arc
   -fmodules`); Swift is not compiled for FFI plugins today.
2. **Manifest** — `watchos/Package.swift` (the CLI discovers the plugin
   through it and links every `.linkedFramework(...)` you declare).
3. **Pubspec** — declare the model and the exported symbols:

   ```yaml
   flutter:
     plugin:
       platforms:
         watchos:
           ffiPlugin: true
           dartPluginClass: <Name>Watchos
           ffiSymbols:
             - <name>_watchos_foo
             - <name>_watchos_bar
   ```

   `ffiSymbols` matters: the CLI emits a forced reference for each so the
   statically linked symbols survive `-dead_strip` and stay resolvable via
   `DynamicLibrary.process()`.
4. **Dart** — a class extending the upstream `*_platform_interface`, with
   a `static void registerWith()` that installs itself as the default
   instance, and methods that call the FFI bindings. Keep the bindings in
   an overridable class with a `forTesting` constructor so unit tests can
   fake them (see `path_provider_watchos`).

## 2. Pick the upstream APIs

Read the upstream `*_platform_interface` and decide per method:

- **Supported** — implement via a watchOS system API
- **Unsupported** — keep the interface's throwing default (or throw
  `UnsupportedError` with a reason)

Document the decision in a table in your `README.md` /
`PORTING_REPORT.md`. Common watchOS "unsupported" reasons:

- No UIKit app surface (UIApplication, UIView/UIViewController, UIDevice —
  use WKApplication / WKInterfaceDevice)
- No WebKit, no camera, no photo library, no pasteboard
- No SFSpeechRecognizer, CallKit, CoreNFC, Vision, PDFKit, CoreTelephony
- No SystemConfiguration reachability (use `NWPathMonitor`, watchOS 6+)
- Platform views are not supported by the embedder

And, unlike tvOS, these DO work — don't stub them reflexively:

- CoreLocation (authorization is shared with the paired iPhone)
- HealthKit, CoreMotion, WatchConnectivity (watch side)
- StoreKit purchasing (watchOS 6.2+; no store UI surfaces)
- ASWebAuthenticationSession (watchOS 6.2+)
- LocalAuthentication `.deviceOwnerAuthentication` (watchOS 9+)
- Haptics via `WKInterfaceDevice.current().play(_:)`

The porter's `PORTING_REPORT.md` lists exactly which handlers hit which of
these — trust it as the checklist.

## 3. Verify

```sh
cd packages/<name>_watchos
flutter test && flutter analyze          # Dart side
cd example && flutter-watchos build watchos --simulator --debug
```

Then confirm the symbols actually made it into the binary:

```sh
nm build/watchos/Debug-watchsimulator/Runner.app/Runner | grep <name>_watchos_
```

Every `ffiSymbols` entry must appear (type `T`). If one is missing, it was
dead-stripped — check the pubspec list and the `used` attribute.

## 4. Versioning & publishing

Match the tvOS repo conventions: `0.0.x` while staged, `0.1.0` for the
first working release, publish under the `flutterwatch.dev` verified
publisher, and keep `CHANGELOG.md` current.
