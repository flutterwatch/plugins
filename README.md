# FlutterWatch Plugins

Flutter plugins with **Apple Watch (watchOS)** support, maintained by the
[flutterwatch.dev](https://flutterwatch.dev) organization.

These are companions to [flutter-watchos](https://github.com/flutterwatch/flutter-watchos)
— the Flutter watchOS custom embedder. Most are federated `*_watchos`
implementations of popular pub.dev plugins, produced with the
`flutter-watchos plugin port` tool and finished/verified by hand.

> **Publishing to pub.dev** under the `flutterwatch.dev` publisher is in
> progress. Each version badge below lights up automatically once its
> package is published; until then, add the package as a git dependency
> (see [Usage](#usage)).

## How watchOS plugins work

watchOS plugins ship native code via **dart:ffi**: the package exports C
symbols from `watchos/Classes/*.m`, declares them under
`flutter.plugin.platforms.watchos.ffiSymbols`, and the `flutter-watchos`
CLI statically links them into the watch binary where Dart resolves them
with `DynamicLibrary.process()`. A plugin can additionally ship **native
SwiftUI platform views** (`watchos/Views/*.swift`) that the CLI compiles
into the app and the plugin embeds with `WatchPlatformView`
(package:flutter_watchos) — see `video_player_watchos`. Method-channel
plugins are **not supported** on watchOS — a package whose `watchos:` block
declares only `pluginClass:` will build but its channel calls throw
`MissingPluginException` (the CLI warns about this at build time).

## List of plugins

Every plugin below has a working watchOS implementation, verified on the
watch simulator. Full details (API coverage, watchOS capability, and
porting notes) are in each package's `README.md` and `PORTING_REPORT.md`.

| Plugin | Upstream | watchOS backend |
|---|---|---|
| [`path_provider_watchos`](packages/path_provider_watchos) [![pub](https://img.shields.io/pub/v/path_provider_watchos.svg)](https://pub.dev/packages/path_provider_watchos) | [`path_provider`](https://pub.dev/packages/path_provider) | `NSSearchPathForDirectoriesInDomains` |
| [`shared_preferences_watchos`](packages/shared_preferences_watchos) [![pub](https://img.shields.io/pub/v/shared_preferences_watchos.svg)](https://pub.dev/packages/shared_preferences_watchos) | [`shared_preferences`](https://pub.dev/packages/shared_preferences) | `NSUserDefaults` |
| [`package_info_plus_watchos`](packages/package_info_plus_watchos) [![pub](https://img.shields.io/pub/v/package_info_plus_watchos.svg)](https://pub.dev/packages/package_info_plus_watchos) | [`package_info_plus`](https://pub.dev/packages/package_info_plus) | `NSBundle` |
| [`device_info_plus_watchos`](packages/device_info_plus_watchos) [![pub](https://img.shields.io/pub/v/device_info_plus_watchos.svg)](https://pub.dev/packages/device_info_plus_watchos) | [`device_info_plus`](https://pub.dev/packages/device_info_plus) | `WKInterfaceDevice` |
| [`battery_plus_watchos`](packages/battery_plus_watchos) [![pub](https://img.shields.io/pub/v/battery_plus_watchos.svg)](https://pub.dev/packages/battery_plus_watchos) | [`battery_plus`](https://pub.dev/packages/battery_plus) | `WKInterfaceDevice` battery |
| [`connectivity_plus_watchos`](packages/connectivity_plus_watchos) [![pub](https://img.shields.io/pub/v/connectivity_plus_watchos.svg)](https://pub.dev/packages/connectivity_plus_watchos) | [`connectivity_plus`](https://pub.dev/packages/connectivity_plus) | `nw_path_monitor` |
| [`flutter_secure_storage_watchos`](packages/flutter_secure_storage_watchos) [![pub](https://img.shields.io/pub/v/flutter_secure_storage_watchos.svg)](https://pub.dev/packages/flutter_secure_storage_watchos) | [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) | Keychain (`SecItem*`) |
| [`network_info_plus_watchos`](packages/network_info_plus_watchos) [![pub](https://img.shields.io/pub/v/network_info_plus_watchos.svg)](https://pub.dev/packages/network_info_plus_watchos) | [`network_info_plus`](https://pub.dev/packages/network_info_plus) | `getifaddrs` (IP; no SSID) |
| [`sensors_plus_watchos`](packages/sensors_plus_watchos) [![pub](https://img.shields.io/pub/v/sensors_plus_watchos.svg)](https://pub.dev/packages/sensors_plus_watchos) | [`sensors_plus`](https://pub.dev/packages/sensors_plus) | CoreMotion (`CMMotionManager`) |
| [`local_auth_watchos`](packages/local_auth_watchos) [![pub](https://img.shields.io/pub/v/local_auth_watchos.svg)](https://pub.dev/packages/local_auth_watchos) | [`local_auth`](https://pub.dev/packages/local_auth) | LocalAuthentication (passcode) |
| [`geolocator_watchos`](packages/geolocator_watchos) [![pub](https://img.shields.io/pub/v/geolocator_watchos.svg)](https://pub.dev/packages/geolocator_watchos) | [`geolocator`](https://pub.dev/packages/geolocator) | CoreLocation (`CLLocationManager`) |
| [`video_player_watchos`](packages/video_player_watchos) [![pub](https://img.shields.io/pub/v/video_player_watchos.svg)](https://pub.dev/packages/video_player_watchos) | [`video_player`](https://pub.dev/packages/video_player) | AVFoundation + AVKit platform view |
| [`audioplayers_watchos`](packages/audioplayers_watchos) [![pub](https://img.shields.io/pub/v/audioplayers_watchos.svg)](https://pub.dev/packages/audioplayers_watchos) | [`audioplayers`](https://pub.dev/packages/audioplayers) | AVFoundation (`AVPlayer`) |
| [`firebase_core_watchos`](packages/firebase_core_watchos) [![pub](https://img.shields.io/pub/v/firebase_core_watchos.svg)](https://pub.dev/packages/firebase_core_watchos) | [`firebase_core`](https://pub.dev/packages/firebase_core) | Firebase Apple SDK (`FirebaseCore`) |
| [`firebase_auth_watchos`](packages/firebase_auth_watchos) [![pub](https://img.shields.io/pub/v/firebase_auth_watchos.svg)](https://pub.dev/packages/firebase_auth_watchos) | [`firebase_auth`](https://pub.dev/packages/firebase_auth) | Firebase Apple SDK (`FirebaseAuth`) |
| [`firebase_storage_watchos`](packages/firebase_storage_watchos) [![pub](https://img.shields.io/pub/v/firebase_storage_watchos.svg)](https://pub.dev/packages/firebase_storage_watchos) | [`firebase_storage`](https://pub.dev/packages/firebase_storage) | Firebase Apple SDK (`FirebaseStorage`) |
| [`firebase_messaging_watchos`](packages/firebase_messaging_watchos) [![pub](https://img.shields.io/pub/v/firebase_messaging_watchos.svg)](https://pub.dev/packages/firebase_messaging_watchos) | [`firebase_messaging`](https://pub.dev/packages/firebase_messaging) | Firebase Apple SDK (`FirebaseMessaging`) |

First-party watch capabilities (platform detection, device info, haptics,
Digital Crown) ship in
[`flutter_watchos`](https://github.com/flutterwatch/flutter-watchos)
itself — check there before adding a plugin.

### Evaluated but not provided

These upstream plugins' core capability does not exist on watchOS, so a
published package would be misleading:

| Plugin | Why not on watchOS |
|---|---|
| [`webview_flutter`](https://pub.dev/packages/webview_flutter) | No WebKit on watchOS — no web view or HTML rendering |
| [`url_launcher`](https://pub.dev/packages/url_launcher) | No generic URL launching; only system `tel:`/`sms:` handoff exists |
| [`google_sign_in`](https://pub.dev/packages/google_sign_in) | No GoogleSignIn watchOS SDK; sign-in is delegated to the paired iPhone |
| [`image_picker`](https://pub.dev/packages/image_picker) | No camera and no photo-picker UI on the watch |
| [`google_maps_flutter`](https://pub.dev/packages/google_maps_flutter) | No Google Maps SDK for watchOS (an Apple MapKit backend would not honestly implement the interface) |

Note the difference from tvOS: **CoreLocation, HealthKit, CoreMotion,
StoreKit purchasing, and (watchOS 9+) LocalAuthentication all exist on the
watch** — plugins built on those are portable, not excluded.

### Feasible but not yet ported

These have a watchOS-viable native backend and are good future additions;
they are simply out of scope for now (large surface or partial support):
`sqflite` (SQLite), `flutter_tts` (AVFoundation),
`wakelock_plus` (only a session-typed `WKExtendedRuntimeSession`, not a
general idle-timer disable), and `cloud_firestore` (the Firebase Apple SDK
ships Firestore's core as a prebuilt binary with no watchOS slice, so a
port needs Firebase's from-source Firestore build; the rest of the
network-viable Firebase family — core, auth, storage, messaging — is
ported above).

## Usage

The upstream plugins do **not** endorse a watchOS implementation, so add
the `*_watchos` package to your app **explicitly**, alongside the upstream
plugin. Until the package is published to pub.dev, depend on it via git:

```yaml
dependencies:
  path_provider: ^2.1.0
  path_provider_watchos:
    git:
      url: https://github.com/flutterwatch/plugins.git
      path: packages/path_provider_watchos
```

Then use the upstream plugin's API exactly as on iOS — the `*_watchos`
implementation registers automatically via Flutter's federated plugin
runner, with no imports or client code changes. Once published these
become plain `^version` dependencies.

A few packages need a writable directory and therefore also
`path_provider_watchos`: e.g. `video_player_watchos` (for
`VideoPlayerController.file`). Their READMEs note this.

## Examples & tests

Each package ships the **upstream plugin's own example** (its demo `lib/` and
its official `integration_test/`) ported verbatim by `flutter-watchos plugin
port --include-example` with a watchOS runner on top, plus a host-side unit
test. The examples and tests are **unmodified** — the example imports only the
app-facing plugin, and the `*_watchos` implementation registers federatedly
with no client code changes. Each is verified on the watch simulator:

```sh
cd packages/<plugin>_watchos/example
flutter-watchos drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/<test-file> -d <watch-sim>
```

The official integration tests **pass on the watch** for path_provider,
network_info_plus, sensors_plus, local_auth, device_info_plus, battery_plus,
connectivity_plus, shared_preferences (64/64), and package_info_plus's
plugin-level `fromPlatform` case — some cases self-skip on non-Android, as
upstream intends. Two upstream tests are written as **phone-UI sweeps** that
pump the demo's scrolling list and find widgets that a ~200 px watch screen
never materialises: package_info_plus's `example` test and
flutter_secure_storage's page-object `app_test`. Those fail on the watch for
viewport reasons, not plugin defects — the FFI implementations are proven by
the plugin-level cases, the host unit tests, and the unified demo. geolocator's
upstream example has **no** `integration_test/` (its Baseflow demo is manual),
so that package is verified by building and running the example on the sim.

Where an official test surfaced a genuine behavioural gap, the fix went into the
**implementation, not the test** — e.g. `shared_preferences_watchos` now throws
`TypeError` on a wrong-typed read (matching every other platform), and
`package_info_plus_watchos` now returns `installerStore` / `installTime` /
`updateTime` natively.

## How this repository was created

These packages were not hand-written from scratch. Each was generated with
the **`flutter-watchos plugin port`** tool (part of
[flutter-watchos](https://github.com/flutterwatch/flutter-watchos)) and then
verified — and where needed finished — by hand.

### 1. Port an upstream plugin

`flutter-watchos plugin port` takes an existing Apple plugin (the iOS
implementation package) and emits a federated `*_watchos` **FFI scaffold**.

```sh
# from a published pub.dev package (what we used):
flutter-watchos plugin port --from-pub shared_preferences_foundation \
  --output packages/shared_preferences_watchos --include-example

# or from git, or from a local path:
flutter-watchos plugin port --from-git https://github.com/foo/bar.git --ref main --output ...
flutter-watchos plugin port ../some_plugin_ios --output ...
```

The exact upstream source for each package is recorded at the top of its
`PORTING_REPORT.md` (e.g. `video_player_watchos` ←
`video_player_avfoundation`, `shared_preferences_watchos` ←
`shared_preferences_foundation`, `audioplayers_watchos` ←
`audioplayers_darwin`).

**What the porter does automatically:** lays out the federated package
(pubspec, `lib/`, `watchos/`, `analysis_options.yaml`, `LICENSE`,
`CHANGELOG.md`), federates through the upstream `*_platform_interface`,
emits an FFI header/`.m` scaffold with the C-symbol declarations wired into
`flutter.plugin.platforms.watchos.ffiSymbols`, generates a
`PORTING_REPORT.md` recording the source, the watchOS capability outlook
(driven by a watchOS API-availability database), and a checklist, and — with
`--include-example` — ports the upstream example app and its official
`integration_test/` verbatim under a watchOS runner.

### 2. Read the porting report

Every package gets a `PORTING_REPORT.md`: the source + version, the watchOS
capability outlook, the FFI surface, every unsupported region with the
reason, and a `## Verification status` table. Read it before trusting a port.

### 3. Implement the native FFI, then verify

The porter emits a **scaffold, not a working backend** (by design — the
native `.m` functions are stubs). The real native implementation is written
by hand against the platform interface, following
[`AUTHORING.md`](AUTHORING.md) and `path_provider_watchos` as the reference.
A package only joins the list once it is green:

```sh
cd packages/<plugin>_watchos/example
flutter-watchos build watchos --simulator --debug          # must be green
cd ..
flutter-watchos test                                        # host unit tests
cd example
flutter-watchos drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/<test-file> -d <watch-sim>      # real native code on-sim
```

### 4. Curate

Packages whose **primary purpose** can't work on watchOS are not shipped —
they are documented under [Evaluated but not provided](#evaluated-but-not-provided)
rather than published broken.

See [`AUTHORING.md`](AUTHORING.md) for the deeper per-plugin recipe.

## Repository layout

```
plugins/
├── packages/<plugin>_watchos/    # one directory per plugin
│   ├── lib/                      # Dart (federated impl + FFI bindings)
│   ├── watchos/Classes/          # native FFI (Objective-C, exported C symbols)
│   ├── watchos/Views/            # native SwiftUI platform views (optional)
│   ├── watchos/Package.swift     # SwiftPM manifest
│   ├── example/                  # upstream example + integration_test, verbatim
│   ├── test/                     # host-side unit tests (FFI bindings faked)
│   ├── PORTING_REPORT.md         # port detail + verification-status table
│   ├── README.md  CHANGELOG.md  LICENSE
└── AUTHORING.md                  # how to add a new one
```

## Contributing

- Federate via the upstream `*_platform_interface`; suffix `_watchos`.
- Ship native code as **dart:ffi** exported C symbols; method-channel
  `pluginClass:`-only plugins are inert on watchOS.
- Guard watchOS-unsupported APIs and document them in the package
  `README.md` and `PORTING_REPORT.md` so users can assess compatibility.
- Add host-side unit tests and, where the upstream has one, its official
  `integration_test/` verbatim — fix gaps in the implementation, never the
  test.
- A package only ships if it builds green and verifies on the watch simulator.

## License

BSD-3-Clause — see [LICENSE](LICENSE). Ported packages retain their upstream
copyright; watchOS additions are © The FlutterWatch Authors.
