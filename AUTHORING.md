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
- No camera, no photo library, no pasteboard
- No WebKit **in the SDK** — the framework ships in the OS, but there are no
  headers or linkable stub, and `WKWebView` is a `UIView`, which watchOS
  SwiftUI cannot host. Web content has to leave the watch (see
  `url_launcher_watchos`, which hands links to the phone via Handoff)
- No SFSpeechRecognizer, CoreNFC, Vision, PDFKit, CoreTelephony
- No SystemConfiguration reachability (use `NWPathMonitor`, watchOS 6+);
  for the Wi-Fi SSID use `NEHotspotNetwork.fetchCurrent`, watchOS 7+
- Platform views are not supported by the embedder

And, unlike tvOS, these DO work — don't stub them reflexively:

- CoreLocation (authorization is shared with the paired iPhone)
- HealthKit, CoreMotion, WatchConnectivity (watch side)
- StoreKit purchasing (watchOS 6.2+; no store UI surfaces)
- ASWebAuthenticationSession (watchOS 6.2+)
- LocalAuthentication `.deviceOwnerAuthentication` (watchOS 3.0+; only
  `.deviceOwnerAuthenticationWithBiometrics` is unavailable)
- CallKit — `CXProvider` / `CXCallController` (watchOS 9+)
- NetworkExtension hotspot — `NEHotspotNetwork` / `NEHotspotConfiguration`
  (watchOS 7+)
- Haptics via `WKInterfaceDevice.current().play(_:)`

The porter's `PORTING_REPORT.md` lists exactly which handlers hit which of
these — trust it as the checklist.

## 2b. Streams and async native APIs — poll, don't call back

FFI has no zero-setup way to invoke Dart from a native callback thread, so
this repo bridges asynchronous CoreMotion / CoreLocation / LocalAuthentication
work with a **cache-and-poll** pattern instead of `NativeCallable`:

- Native starts updates and stores the *latest* value (a struct guarded by an
  `os_unfair_lock`, or a `dispatch_once`-cached one-shot); it exposes a
  `read_*` that copies the current value into a caller buffer and returns
  whether one is available.
- Dart exposes the interface `Stream` via a broadcast `StreamController` that,
  on first listen, calls the native `start_*` and a `Timer.periodic` reading
  the cache; on cancel it stops updates. One-shot async calls (e.g.
  `evaluatePolicy`, `getCurrentPosition`) `await Future.delayed` between polls
  until the native state flips or a deadline passes.

See `sensors_plus_watchos` (streams), `geolocator_watchos` (permission +
stream + one-shot) and `local_auth_watchos` (async poll) for worked examples.

## 2c. Native SwiftUI platform views

A plugin whose feature needs a native rendering surface (video, maps, …) can
ship **SwiftUI view sources** alongside its FFI classes — no pubspec keys,
discovery is by shape, like the `.m` sources:

1. **Swift** — put the views under `watchos/Views/*.swift`. Expose a
   C-callable registration entry point that registers a factory per view
   type with the CLI-provided `FlutterWatchOSPluginViews` API:

   ```swift
   @_cdecl("<name>_register_views")
   public func registerViews() {
       FlutterWatchOSPluginViews.register("<view-type>") { params in
           AnyView(MyNativeView(params: params))
       }
   }
   ```

   The factory runs on the main thread; `params` is the Dart widget's
   `creationParams` string. To reach the plugin's own C functions from
   Swift, declare them with `@_silgen_name` (see `video_player_watchos`).
2. **Pubspec** — list the registration symbol under `ffiSymbols` so it
   survives the static link.
3. **Dart** — call the registration symbol from `registerWith()`, and embed
   the view with `WatchPlatformView` from `package:flutter_watchos`
   (≥ 0.1.0-beta.5). Pick the layer deliberately: `belowFlutter` when
   Flutter content must draw over the view and gestures stay in Dart (what
   `video_player_watchos` does), the default overlay when the native view
   itself is interactive.

Constraints to document in your README: the view rect is axis-aligned (no
`Transform` of the native surface), and scene snapshots (golden tests)
don't capture native pixels. On an app created by an older flutter-watchos
the views simply don't render (`WatchPlatformView.isSupported`).

**Threading rule:** FFI entry points run on the Flutter UI thread, not the
main thread. Any native object your platform view displays (an `AVPlayer`
attached to AVKit's `VideoPlayer`, a map camera, …) must only be **mutated
on the main queue** — mutating it from the FFI thread opens CATransactions
there, whose run-loop flush performs UIKit layout off-main and aborts in
`_AssertAutoLayoutOnAllowedThreadsOnly`. Hop mutations with
`dispatch_async(dispatch_get_main_queue(), …)` (the serial main queue also
orders create → control → dispose); keep reads lock-guarded on the calling
thread. See `video_player_watchos_ffi.m` (`VPWOnMain`) for the pattern —
and note this class of bug can pass integration tests by timing luck, so
soak the example interactively too.

Two watchOS gotchas these surfaced:

- **Some iOS enum constants do not exist on watchOS** and cannot even be
  *referenced* — e.g. `LAPolicyDeviceOwnerAuthenticationWithBiometrics`. Guard
  the capability in Dart and never name the constant in the `.m`, or the build
  fails with "unavailable: not available on watchOS".
- **The Simulator has no motion hardware and no enrolled passcode/location**,
  so sensor streams emit nothing and interactive prompts block. Keep on-sim
  integration tests to the non-interactive query paths; assert the interactive
  paths on a physical watch. Also gate the interactive test cases so they can't
  hang the suite (they present system UI with no one to answer).

## 2d. Linking an external native SDK (SwiftPM)

A plugin can depend on an external native SDK by declaring it in
`watchos/Package.swift` like any SwiftPM package: add the `.package(url:)`
dependency and the `.product` to the target, and list the system
frameworks/libraries the SDK needs under `linkerSettings`. The
`flutter-watchos` CLI resolves and builds the package graph with
xcodebuild's SwiftPM, harvests the resulting objects (deduplicating
modules shared between plugins, e.g. `FirebaseCore`/`GoogleUtilities`
across the `firebase_*_watchos` family), and force-loads them into the
app — no CocoaPods, no manual Xcode configuration.

Constraints:

- The SDK must **build from source for watchOS** — its manifest declares
  `.watchOS(…)` and every product you pull in compiles for the watch. A
  product that wraps a prebuilt `.binaryTarget` without a watchOS slice
  cannot link (this is what blocks `cloud_firestore`).
- Only name system frameworks that exist on watchOS in `linkerSettings`
  (e.g. `SystemConfiguration` does not).
- SDK calls are network-backed and asynchronous — bridge them with a
  **begin/poll token pattern**: `begin(requestJSON)` starts the operation
  and returns a token, `poll(token)` reports pending/done-with-result, and
  the Dart side polls on a short `Timer`. See `firebase_auth_watchos` for
  the canonical shape.
- A plugin that needs **app-level `WKApplicationDelegate` callbacks**
  (remote notifications) observes the `NSNotification`s the
  `flutter-watchos` runner's `FlutterWatchOSAppDelegate` rebroadcasts —
  by literal name, no compile-time coupling. See `firebase_messaging_watchos`
  and the flutter-watchos plugins doc for the notification names.

The four `firebase_*_watchos` packages (core, auth, storage, messaging)
are worked examples of all of the above.

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

Finally, run the real native code end-to-end on the simulator. Ship the
**upstream plugin's own example and its official `integration_test` verbatim** —
`flutter-watchos plugin port --include-example` ports both, unmodified, with a
watchOS runner on top. Do **not** hand-write a substitute test: if an official
test surfaces a real behavioural gap, fix the **implementation**, not the test.
Then:

```sh
cd example
flutter-watchos drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/<official-test-file> -d <watch-sim-id>
```

(The "integration_test plugin was not detected" warning is benign — results
are still captured over the VM service.)

### Verification-status standard

Every `PORTING_REPORT.md` opens with a `## Verification status` table so the
whole repo is graded the same way:

| Aspect | What it records |
|---|---|
| Implementation | `✅ Working (<backend> FFI)` once the scaffold is finished |
| watchOS capability | `Full`, or `Partial — <what is dropped and why>` |
| Host unit tests | `✅ pass` (FFI bindings faked) |
| Upstream integration test | see marking below |
| Unified demo | `✅ included` in our internal test app |

Marking: **✅** full / passes verbatim · **◐** partial — an official test that is
viewport- or mobile-UI-bound and can't be driven on a ~200 px watch screen (give
the reason; plugin correctness is still covered by host tests + demo) · **○** no
upstream integration test exists (verify by build + run) · **✗** unsupported on
watchOS. Keep the table honest — a red official test stays red and is marked
`◐`, never quietly skipped or replaced.

## 4. Versioning & publishing

Match the tvOS repo conventions: `0.0.x` while staged, `0.1.0` for the
first working release, publish under the `flutterwatch.dev` verified
publisher, and keep `CHANGELOG.md` current.
