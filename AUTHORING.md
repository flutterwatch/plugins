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
   functions marked `__attribute__((visibility("default")))
   __attribute__((used))`.
   Objective-C is fine (the CLI compiles `.m/.mm/.c` with `-fobjc-arc
   -fmodules`). Swift is compiled too: the `.swift` files under `watchos/`
   (not `Package.swift`) go into a module of the plugin's own, which is how
   a plugin ships native views (§2c).
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

   `ffiSymbols` lists the C symbols your Dart code looks up, so keep it
   complete. The list is not what keeps them in the app; the build is. The
   CLI compiles the plugin sources into one static archive and links it with
   `-force_load`, so no object is left out. `used` keeps each function
   through dead-stripping, and default visibility puts it in the binary's
   export table, where `DynamicLibrary.process()` finds it. The CLI also sets
   `STRIP_STYLE = non-global`, so the strip of an App Store build keeps the
   exports. §3 shows how to check a build. A plugin can also map macros to
   app Info.plist keys under `defines`, to leave out the code for an API an
   app does not use (§2e).
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
- Native SwiftUI views, embedded as platform views (§2c)

The porter's `PORTING_REPORT.md` lists exactly which handlers hit which of
these — trust it as the checklist.

## 2b. Streams and async native APIs

`NativeCallable.listener` **works on the watchOS engine** — native code can wake
Dart from a background thread. Verified in release/AOT on a physical watch:
5 callbacks fired from a global dispatch queue, 5 received in order, no drops.
So push is available, and a new streaming plugin should prefer it.

`flutter_watch_link` is the worked example. The rule that matters
there: **the callback carries a kind, never a payload.** `NativeCallable
.listener` is asynchronous, so native returns before Dart runs and any pointer
handed across could be freed in between. Signal that something changed, keep a
bounded native buffer, and let Dart pull the data back with synchronous reads —
a burst can still outrun the isolate, and a ring buffer with a drop counter is a
better failure mode than unbounded growth.

### Cache-and-poll, the older pattern

Several plugins still bridge asynchronous native work with **cache-and-poll**,
which predates the finding above: `audioplayers_watchos`,
`battery_plus_watchos`, `video_player_watchos`, `in_app_purchase_watchos` and
the three `firebase_*_watchos` packages. It is still correct, and still the
simpler option for a one-shot call; it is no longer the only option, and it is
the wrong default for anything long-lived:

- Native starts updates and stores the *latest* value (a struct guarded by an
  `os_unfair_lock`, or a `dispatch_once`-cached one-shot); it exposes a
  `read_*` that copies the current value into a caller buffer and returns
  whether one is available.
- Dart exposes the interface `Stream` via a broadcast `StreamController` that,
  on first listen, calls the native `start_*` and a `Timer.periodic` reading
  the cache; on cancel it stops updates. One-shot async calls (e.g.
  `evaluatePolicy`, `getCurrentPosition`) `await Future.delayed` between polls
  until the native state flips or a deadline passes.

For **push** — what a new streaming plugin should do — see
`sensors_plus_watchos` (four streams sharing one callback, fanned out on a
sensor kind), `geolocator_watchos` (a stream and two one-shots sharing one
callback through a small notifier) and `local_auth_watchos` (a one-shot future
that must also handle resolving *before* Dart registers).

Four rules those three earned the hard way:

- **Native holds one callback pointer, not one per consumer.** If more than one
  thing can wait at once, fan out from a single trampoline — registering per
  consumer lets whichever finishes first silence the others.
- **A consumer is a *subscription*, not a stream or a call site.** Keying the
  fan-out by sensor, by stream, or by "the current call" is the same bug one
  level down: a second `listen` on the same sensor, a second `authenticate()`,
  a second listener on the same connectivity stream. Keep a `Set` of callbacks
  per waited-on thing, notify all of them, and unregister native only when the
  set empties — a copy of the set while notifying, since a listener may remove
  itself as it settles.
- **Check the state once immediately after starting.** A native operation can
  resolve synchronously inside the call that begins it, so the signal is gone
  before Dart could register for it, and waiting alone deadlocks.
- **Keep the trampoline; unregister the pointer.** A `NativeCallable` is only
  reclaimed by `close()`, and `close()` is exactly what cannot be called while
  native might be between reading the pointer and calling it. So allocate one
  per plugin, `setCallback(nullptr)` when nobody is waiting, and re-register
  the *same* one on the next listen. Allocating a fresh one per cycle — or
  appending each to a `_retained` list — leaks one per subscription for the
  life of the app.

A **broadcast controller's `onListen` fires only on zero-to-one**, so it is the
wrong place to seed a "current value". A second concurrent subscriber gets
nothing until something changes. Use `Stream.multi` and seed each subscriber:
`connectivity_plus_watchos` and `flutter_watch_link`'s `states` both do.

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
2. **Pubspec** — list the registration symbol under `ffiSymbols`, next to
   the plugin's other exports.
3. **Dart** — call the registration symbol from `registerWith()`, and embed
   the view with `WatchPlatformView` from `package:flutter_watchos` (depend
   on its current version, `flutter_watchos: ^0.1.0`). On an engine
   that composites platform views (`WatchPlatformView.isComposited`; the
   engine of every flutter-watchos from 0.1.0 does) the view sits in paint
   order — Flutter content painted after it draws over it — and `layer:`
   only decides who gets touches: `belowFlutter` when gestures should stay
   in Dart (what `video_player_watchos` does), the default `aboveFlutter`
   when the native view itself is interactive.

Constraints to document in your README: scene snapshots (golden tests)
don't capture native pixels, and on an engine that predates the compositor
(`WatchPlatformView.isComposited` is false) the view rect is axis-aligned
(no `Transform` of the native surface). On an app created by an older
flutter-watchos the views simply don't render
(`WatchPlatformView.isSupported`).

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

## 2e. Compiling out what an app does not use

App Store Connect asks for the usage description of each privacy-sensitive
API a binary references (ITMS-90683), whether or not the app calls it. A
plugin that covers several such APIs can leave out the ones an app does not
use, as permission_handler's iOS implementation does with its `PERMISSION_*`
macros. Map each macro to the app Info.plist key that turns it on, under
`defines:` next to `ffiSymbols`:

```yaml
flutter:
  plugin:
    platforms:
      watchos:
        ffiPlugin: true
        dartPluginClass: <Name>Watchos
        defines:
          <NAME>_CONTACTS: NSContactsUsageDescription
          <NAME>_LOCATION:
            - NSLocationWhenInUseUsageDescription
            - NSLocationAlwaysAndWhenInUseUsageDescription
```

From the first flutter-watchos release after 0.1.1, the CLI compiles the
plugin's native sources with `-D<MACRO>=1` (in Swift, `-D<MACRO>`) for each
macro whose key the watch app's Info.plist sets. A plugin that declares
`defines` also gets the marker, `FLUTTER_WATCHOS_PLUGIN_DEFINES`, on every
source. A plugin without `defines`, or whose `defines` is misspelled or
misplaced, does not get it, and compiles as before. An older CLI passes
neither, so guard each group to keep it in apps built by one:

```objc
#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES) || <NAME>_CONTACTS
// The contacts code.
#endif
```

- Give a group that is left out an answer: `permission_handler_watchos`
  answers as the iOS implementation answers a permission it does not know.
  Where upstream compiles a group in with any of several macros, keep its
  answers for the parts whose own macro is off, as
  `permission_handler_watchos` does for calendar and reminders. Leave such a
  part out instead only when keeping it would put into the app something
  the app must then declare, and say so in the README. The one case in
  `permission_handler_watchos` is location: under
  `PERMISSION_LOCATION_WHENINUSE` alone it answers `locationAlways` as a
  permission it does not know, where upstream reads its status, so that an
  app that only asks for "when in use" has no `NSUserDefaults` flag, a
  required-reason API its privacy manifest would have to declare.
- Keep the macros and keys in the pubspec and in the sources paired: a
  misspelled macro, or a key filed under the wrong one, puts the wrong code
  into every app, and nothing fails to compile. File each key under one
  macro. A key read in code that several macros compile in belongs to the
  one no other key turns on: `NSLocationWhenInUseUsageDescription`, read
  under `PERMISSION_LOCATION || PERMISSION_LOCATION_WHENINUSE`, belongs to
  `PERMISSION_LOCATION_WHENINUSE`. `permission_handler_watchos` has tests
  that check each key the native code reads against the guards around it
  this way.
- `tool/check_native_sources.sh` compiles such a plugin with no `-D`, with
  the marker and every macro, with the marker alone, and with the marker and
  each macro alone (see `tool/README.md`).
- The CLI compiles plugin sources on every `flutter-watchos build` and
  `run` (and `drive`, and `test` with `-d`); an Xcode build or archive does
  not. `run` and `test` stage a debug build for one SDK, and `test` without
  `-d` compiles no plugin source, so after an Info.plist edit an app runs
  `flutter-watchos build watchos --release` again before it archives.
- If the CLI cannot read the app's Info.plist, it warns and compiles the
  plugin without its macros and without the marker, as an older CLI does.

The rules, which values turn a macro on, what `-v` prints and why a plugin
built through SwiftPM (§2d) is not covered, are in the CLI's
`doc/plugins.md`, from the first flutter-watchos release after 0.1.1.
`permission_handler_watchos` is the worked example.

## 3. Verify

```sh
cd packages/<name>_watchos
flutter test && flutter analyze          # Dart side
cd example && flutter-watchos build watchos --simulator --debug
```

Then confirm the exports made it into the app. A debug build puts the app's
code in `Runner.debug.dylib`, next to a small `Runner` launcher, so check
that file:

```sh
dyld_info -exports build/watchos/Debug-watchsimulator/Runner.app/Runner.debug.dylib | grep <name>_watchos_
```

`dyld_info -exports` prints the export table, which is what
`DynamicLibrary.process()` searches. Every `ffiSymbols` entry must be listed.
If one is missing, check the `used` attribute and the default visibility on
its definition. A release build keeps the app's code in `Runner` itself: run
`dyld_info -arch arm64 -exports` on
`build/watchos/Release-watchos/Runner.app/Runner` (its `arm64_32` slice is a
stub without Flutter code).

Finally, run the real native code end-to-end on the simulator. Ship the
**upstream plugin's own example and its official `integration_test`** —
`flutter-watchos plugin port --include-example` ports both, unmodified, with a
watchOS runner on top. The example stays upstream's code, except for these
watch deviations, each listed in the package `README.md` and
`PORTING_REPORT.md`:

- `Platform.isIOS` becomes `FlutterWatchosPlatform.isIos` where the call it
  guards reaches a plugin with no watchOS implementation.
- A missing `*_watchos` package is added to the example's pubspec.
- A dependency that upstream's example takes from upstream's repository,
  because it is not on pub.dev, is pinned with `ref` to the commit of the
  upstream release the package is tested against.
- An upstream comment with a forbidden word is reworded.

If upstream's example cannot launch on the watch even with these deviations
(for example, its start-up calls a plugin that has no watchOS
implementation), ship a small watch demo of the app-facing API instead, and
say why in an `## Example` section of `PORTING_REPORT.md`. The official
`integration_test` still ships. A limit that only part of the example hits,
such as a link the watch cannot open, is not a reason: use a deviation, or
record the limit in the verification table.

The official tests stay verbatim. Do **not** hand-write a substitute test: if
an official test surfaces a real behavioural gap, fix the **implementation**,
not the test. A test for behaviour the official ones do not cover goes next
to them, named `watchos_<topic>_test.dart` so it is not taken for an upstream
test. Then:

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

### pub.dev points and platforms

pana, the tool behind the points on pub.dev, scores support for six
platforms: Android, iOS, Linux, macOS, web and Windows. watchOS is not one
of them, so a package that implements only watchOS gets 0 of the 20
"Platform support" points, and 140/160 is the most it can score. That is
expected, and there is nothing to fix.

Declare only the platforms the package implements. An `ios:` (or any other)
block added for the points would tell users the package works there when it
does not, and on those platforms the upstream plugin already does the work.
`flutter_watch_link` declares `ios:` legitimately: it has no upstream, and it
implements the iPhone side of WatchConnectivity itself, from the same `src/`
as its watch side, so it scores 160.
