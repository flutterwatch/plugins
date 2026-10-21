# permission_handler_watchos — porting report

## Verification status

| Aspect | Result |
|---|---|
| Implementation | ✅ Working (FFI; one strategy per permission group, as in the iOS implementation) |
| watchOS capability | ◐ The permissions watchOS has: location (when in use and always), notifications, sensors, microphone, contacts, calendar (full access and write only), reminders, Bluetooth. The others answer as iOS answers for a permission it does not know |
| Host unit tests (`flutter test`) | ✅ 6 pass |
| Upstream integration test | ○ none upstream (Baseflow's example is a manual demo) |
| watchOS integration test (`example/integration_test/permission_handler_test.dart`) | ✅ 4 pass on the watchOS 27.0 Simulator |
| System prompts | ✅ asked for on the Simulator, each answered as on iOS: notification granted; location when in use granted; location always kept at "while using" → permanentlyDenied; sensors granted; microphone granted; contacts refused → permanentlyDenied; reminders granted; calendar write only granted. Bluetooth reads granted on the Simulator, which has no Bluetooth |
| Physical watch | not yet checked |

Marking: ✅ full / passes · ◐ partial — reason given · ○ not applicable (no upstream test) · ✗ unsupported on watchOS.

> This scaffold has been **finished by hand** into a working FFI package; see
> the status above. The generated notes below are kept for provenance.

## Design

The iOS implementation compiles each permission group in or out with a
preprocessor macro (`PERMISSION_CONTACTS=1` and so on, all off by default), so
that an app does not reference an API it never asks for: App Store Connect
warns about a missing usage description for every privacy API a binary
references. A watch app has no Podfile to set those macros, so this package
gets the same result at runtime instead: each framework is loaded with
`dlopen` and its classes looked up by name the first time a permission of
its group is asked about, and only messaged. Of the frameworks, only
UserNotifications, which needs no usage description, is linked. `nm -u` on
the compiled objects shows no class of CoreLocation, CoreMotion, AVFAudio,
Contacts, EventKit or CoreBluetooth.

watchOS terminates an app that asks for a permission without its usage
description. Before each prompt this package checks the Info.plist key the
prompt needs and fails the request with a `PlatformException` whose code is
`MISSING_USAGE_DESCRIPTION`, the code the iOS implementation uses for
location, instead.

Each call returns a request id at once; the strategy answers on its own
queue, native keeps the answer as JSON, and wakes Dart through one
`NativeCallable.listener` that carries a kind, never a payload. Dart asks for
the permissions of `requestPermissions` one at a time, as the watch shows one
prompt at a time.

An "always" location request kept at "while using" changes nothing, so
CoreLocation sends no delegate call. As in the iOS implementation, the app
becoming active again after the prompt (`WKApplicationDidBecomeActiveNotification`)
is the answer then, and a second request answers without a prompt that
watchOS would not show again.

## Permission coverage

| Permission | watchOS |
|---|---|
| `notification` | ✅ UNUserNotificationCenter: alert, sound and badge, as on iOS; provisional is reported. The iOS implementation also registers for remote notifications after a grant; this package does not, which is firebase_messaging_watchos's job on the watch |
| `location`, `locationWhenInUse`, `locationAlways` | ✅ CLLocationManager; service status is `locationServicesEnabled` |
| `sensors` | ✅ CMMotionActivityManager, asked for with an activity query as on iOS; service status is `isActivityAvailable` |
| `microphone` | ✅ AVAudioApplication's record permission (watchOS 10 and later) |
| `contacts` | ✅ CNContactStore; `limited` from watchOS 11 |
| `calendarFullAccess`, `calendarWriteOnly`, `calendar`, `reminders` | ✅ EKEventStore, with the full-access and write-only requests from watchOS 10 |
| `bluetooth` | ✅ CBCentralManager: creating it asks, its first state update answers; service status is whether it is powered on |
| `camera`, `photos`, `photosAddOnly`, `mediaLibrary`, `speech`, `appTrackingTransparency`, `backgroundRefresh`, `phone` | ✗ not on watchOS: `denied`, a request `permanentlyDenied`, service `disabled`, as iOS answers for an unknown permission |
| `criticalAlerts`, `assistant` | ✗ not implemented yet: they need an entitlement each (critical alerts, Siri); answered as an unknown permission |
| The Android-only permissions | answered as an unknown permission, as on iOS |

## Interface coverage

| Member | watchOS |
|---|---|
| `checkPermissionStatus` | ✅ |
| `checkServiceStatus` | ✅ |
| `requestPermissions` | ✅ one at a time |
| `shouldShowRequestPermissionRationale` | ✅ false, as on iOS |
| `openAppSettings` | ✗ false: watchOS has no settings page an app can open |

## Example

permission_handler's own example is a phone app built on
`baseflow_plugin_template`, whose `url_launcher` links do not run on the watch,
so `example/lib/main.dart` is a small watch demo instead: every permission
watchOS has, with its status, asked for on a tap. The example's Info.plist has
the usage description of each.

Generated by `flutter-watchos plugin port` on 2026-10-21.

Source: `permission_handler_apple` 9.6.2 (path: `/Users/iamoguzhanarslantas/.pub-cache/hosted/pub.dev/permission_handler_apple-9.6.2`)
Base platform: ios (Objective-C)
Output: `./permission_handler_watchos`

## APIs the source plugin used

### Not available on watchOS

These iOS/macOS APIs have **no watchOS equivalent** — the capability must be omitted or redesigned (often via the paired iPhone):

| API | Used at | Why / watchOS note |
|---|---|---|
| AVCaptureCamera | `ios/permission_handler_apple/Sources/permission_handler_apple/strategies/AudioVideoPermissionStrategy.m:58` (+1 more) | AVFoundation exists on watchOS but the capture stack does not — there is no camera. Camera features must be omitted; the rest of the plugin's AVFoundation use (players, audio) can stay. |
| CoreTelephony | `ios/permission_handler_apple/Sources/permission_handler_apple/strategies/PhonePermissionStrategy.m:8` (+6 more) | CoreTelephony is not available on watchOS — even cellular watch models do not expose carrier/cellular-plan APIs to apps. There is no watchOS replacement; the feature must be omitted. |
| Photos | `ios/permission_handler_apple/Sources/permission_handler_apple/strategies/PhotoPermissionStrategy.h:11` (+4 more) | The Photos library framework is not available on watchOS. |
| SpeechRecognition | `ios/permission_handler_apple/Sources/permission_handler_apple/strategies/SpeechPermissionStrategy.m:27` (+2 more) | The Speech framework is not available on watchOS. System dictation is reachable only through WatchKit text input (`presentTextInputController`), which the Flutter watchOS engine already drives for text fields — a custom speech pipeline has no watchOS port. |
| UIApplication | `ios/permission_handler_apple/Sources/permission_handler_apple/strategies/BackgroundRefreshStrategy.m:25` (+4 more) | UIApplication does not exist on watchOS — the app object is WKApplication (watchOS 7+) / WKExtension. For opening URLs, use `openSystemURL(_:)`. It reliably handles tel: and sms:, and — despite the documentation listing only those — it also accepts http/https, presenting the system web sheet. Verified on a physical watch (watchOS 26.5): for a third-party app that sheet declines to render and shows "URL failed to load — this url can be viewed on your iPhone", even for a trivial page. Pair it with an NSUserActivity (NSUserActivityTypeBrowsingWeb) so the phone can actually pick the link up — see url_launcher_watchos. |

### Available, but review

These work on watchOS (often differently than iOS) — implement them, checking the note:

| API | Used at | watchOS note |
|---|---|---|
| CoreLocation | `ios/permission_handler_apple/Sources/permission_handler_apple/strategies/LocationPermissionStrategy.m:17` (+9 more) | CoreLocation IS available on watchOS: requestLocation, continuous updates, and heading (watchOS 6+) work, with GPS on cellular/GPS models and phone-assisted fixes otherwise. Differences to review: authorization is shared with the paired iPhone app when one exists, region monitoring is limited, and background location needs a workout or background-refresh context. |

## Checklist

- [x] Declare your C functions in `watchos/Classes/permission_handler_watchos_ffi.h` and implement them in the `.m`, one per platform-interface method you support.
- [x] List every exported symbol under `ffiSymbols` in `pubspec.yaml`, and the frameworks you link in `Package.swift`.
- [x] Add a `lookupFunction` binding per symbol in the Dart `Bindings` class and override the platform-interface methods.
- [x] Add the package to a watchOS app (`flutter-watchos create` one if needed), build for `watchsimulator`, then `nm` the binary to confirm your `ffiSymbols` are present (type `T`).
- [x] Bump the version and update `CHANGELOG.md` before publishing.

---

See the finished plugins in the `flutterwatch/plugins` repo (e.g. `path_provider_watchos`, `battery_plus_watchos`) for worked examples of this exact shape.
