# permission_handler_watchos — porting report

## Verification status

| Aspect | Result |
|---|---|
| Implementation | ✅ Working (FFI; one strategy per permission group, as in the iOS implementation) |
| watchOS capability | ◐ The permissions watchOS has: location (when in use and always), notifications, critical alerts, sensors, microphone, contacts, calendar (full access and write only), reminders, Bluetooth, Siri; storage is granted as on iOS. The others answer as iOS answers for a permission it does not know |
| Host unit tests (`flutter test`) | ✅ 12 pass; 4 of them check that the pubspec's `defines` and the native guards pair each key with the macro of the guard around the code that reads it |
| Upstream integration test | ○ none upstream (Baseflow's example is a manual demo) |
| watchOS integration test (`example/integration_test/permission_handler_test.dart`) | ✅ 5 pass on the watchOS 27.0 Simulator |
| System prompts | ✅ asked for on the Simulator, each answered as on iOS: notification granted; location when in use granted; location always kept at "while using" → permanentlyDenied; sensors granted; microphone granted; contacts refused → permanentlyDenied; reminders granted; calendar write only granted. Bluetooth reads granted on the Simulator, which has no Bluetooth. After the review fixes, location when in use again: the prompt closed with the crown → answered, and a second request prompted again; allowed → granted; "always" asked for right after → its prompt stayed up until answered, kept at "while using" → permanentlyDenied. In upstream's example: calendar (full access) allowed → granted |
| Critical alerts and Siri prompts | not yet asked for: each needs an entitlement the example does not have |
| Compile-time groups | ✅ `tool/check_native_sources.sh` compiles the sources with no `-D` (flutter-watchos 0.1.1 or earlier), with the marker and every macro, with the marker alone, and with the marker and each macro alone, for a watch and the Simulator; each pair of the events macros was compiled too (Xcode 27.1, no warning). Objects compiled with the marker alone hold none of the groups' class names, selectors or keys (`strings`), and none of their frameworks' link entries; with `PERMISSION_LOCATION_WHENINUSE` alone, no "always" request and no `NSUserDefaults` reference (`nm -u`). The events strategy, built for macOS with EventKit's status and requests stubbed, answered every combination of its three macros as the iOS implementation does: each status read, the service not applicable, a request whose prompt is left out answering its status without a prompt |
| App Store Connect upload | not yet done. With the first flutter-watchos release after 0.1.1, a group the app does not use is left out (see "Design"); whether ITMS-90683 reads the class names of such groups under 0.1.1 or earlier is unchecked |
| Example deviations | `example/pubspec.yaml` adds `url_launcher_watchos`, for the links of `baseflow_plugin_template`, which go through `url_launcher`. `example/lib/main.dart` is otherwise upstream's, formatted as this repo's CI checks |
| Physical watch | not yet checked |

Marking: ✅ full / passes · ◐ partial — reason given · ○ not applicable (no upstream test) · ✗ unsupported on watchOS.

> This scaffold has been **finished by hand** into a working FFI package; see
> the status above. The generated notes below are kept for provenance.

## Design

The iOS implementation compiles each permission group in or out with a
preprocessor macro (`PERMISSION_CONTACTS=1` and so on, all off by default), so
that an app does not reference an API it never asks for: App Store Connect
warns about a missing usage description (ITMS-90683) for the privacy APIs a
binary references. A watch app has no Podfile to set those macros. Instead,
the pubspec maps the same macros to the Info.plist keys each group's prompts
check, under `defines`, and from the first flutter-watchos release after
0.1.1 the CLI reads the app's Info.plist on every build and compiles the
plugin with the macro of each group whose key is set, after
`FLUTTER_WATCHOS_PLUGIN_DEFINES`. Each group's file guards its code with
`#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES) || PERMISSION_X` and gives the
dispatch table, through one function, either its strategy or
`PHWUnknownStrategy`, which answers as the iOS implementation answers a group
whose macros are all off. A group left out takes its framework's class names,
selectors, usage-description keys and import out of the binary.

The calendar and reminders group follows the iOS implementation exactly: any
of `PERMISSION_EVENTS_FULL_ACCESS`, `PERMISSION_EVENTS` and
`PERMISSION_REMINDERS` compiles its strategy in, which then reads the real
EventKit status of all four permissions and answers the service as not
applicable. Each macro adds the prompts its key allows; the full-access one
allows the write-only prompt too. A request whose prompt is left out answers
its status without a prompt.

Location goes further than the iOS implementation. There,
`PERMISSION_LOCATION_WHENINUSE` alone still compiles the whole location
strategy, `locationAlways` included, and only the "always" request is left
out. Here `PERMISSION_LOCATION_WHENINUSE` alone compiles in "when in use",
and `locationAlways` answers as an unknown permission, without its request
and its `NSUserDefaults` flag; `PERMISSION_LOCATION` compiles in "always"
too.

A flutter-watchos that predates `defines` passes neither the macros nor the
marker, and nor does a later one that cannot read the app's Info.plist, so
every group is compiled into every app, as before. Each framework
is loaded with `dlopen` and its classes looked up by name the first time a
permission of its group is asked about, and only messaged; of the
frameworks, only UserNotifications, which needs no usage description, is
linked. `nm -u` on the compiled objects shows no class symbol of
CoreLocation, CoreMotion, AVFAudio, Contacts, EventKit, CoreBluetooth or
Intents. That is not the iOS result: the class names, selectors and delegate
protocol metadata are still in the binary, and Apple does not document
whether its check reads those. Until an App Store Connect upload of an app
that uses only notifications shows no ITMS-90683, the README tells apps
built with such a flutter-watchos to expect to need every group's usage
description.

The location strategy keeps one flag in `NSUserDefaults` (whether "always"
was asked for), a required-reason API; the iOS implementation ships a
privacy manifest for the same reason. The flag is compiled in with
`PERMISSION_LOCATION` only, or with no `defines` applied. The README shows
the entry an app's manifest needs.

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

A location prompt closed without an answer, with the crown, sends no
delegate call on watchOS, not even the second "not determined" report the
iOS implementation takes as that (seen on the watchOS 27.0 Simulator). The
app becoming active again answers then, if it resigned active since the
request (the prompt taking the screen does that): with the status at that
moment, or, if it is still "not determined" a second later, denied. An
answer from the delegate in that second stands the re-read down, so a
request made right after, such as "always" after "when in use", is not
answered by it.

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
| `contacts` | ✅ CNContactStore; the watchOS SDK has no limited access |
| `calendarFullAccess`, `calendarWriteOnly`, `calendar`, `reminders` | ✅ EKEventStore, with the full-access and write-only requests. With only some of the group's keys, each status is still read, and a request whose prompt is left out answers its status without a prompt, as on iOS |
| `bluetooth` | ✅ CBCentralManager: creating it asks, its first state update answers; service status is whether it is powered on |
| `criticalAlerts` | ✅ UNUserNotificationCenter's critical alert setting and request; needs the Critical Alerts entitlement |
| `assistant` | ◐ INPreferences (watchOS 6+), Siri, for an app that opts in; needs the Siri capability. INPreferences throws in an app without it (seen on the Simulator), so the Info.plist key `PermissionHandlerWatchosSiri` (`YES`) is the opt-in, and from the first flutter-watchos release after 0.1.1 the same key turns the iOS implementation's `PERMISSION_ASSISTANT` macro on. The opt-in reads the key by the CLI's rule, so the two agree: a non-empty string, `NO` included, opts in as the Boolean `YES` does; `NSSiriUsageDescription`, which apps on an older flutter-watchos add with every other group's, does not switch it on. Without the opt-in Siri's code is left out and Siri answers as an unknown permission (a request `permanentlyDenied`), or, under 0.1.1 or earlier, the status is `denied` and so is a request; with it and no `NSSiriUsageDescription`, a request fails with `MISSING_USAGE_DESCRIPTION` |
| `storage` | ✅ granted, service not applicable, as on iOS |
| `camera`, `photos`, `photosAddOnly`, `mediaLibrary`, `speech`, `appTrackingTransparency`, `backgroundRefresh`, `phone` | ✗ not on watchOS: `denied`, a request `permanentlyDenied`, service `disabled`, as iOS answers for an unknown permission |
| The Android-only permissions | answered as an unknown permission, as on iOS |

## Interface coverage

| Member | watchOS |
|---|---|
| `checkPermissionStatus` | ✅ |
| `checkServiceStatus` | ✅ |
| `requestPermissions` | ✅ one at a time; another call while one waits fails with `ERROR_ALREADY_REQUESTING_PERMISSIONS`, as on iOS |
| `shouldShowRequestPermissionRationale` | ✅ false, as on iOS |
| `openAppSettings` | ✗ false: watchOS has no settings page an app can open |

## Example

`example/lib/main.dart` is permission_handler_apple 9.6.3's own example,
unchanged but for the formatting this repo's CI checks: a phone app on `baseflow_plugin_template` that lists every
permission, shows its status and asks for it on a tap. It runs on the watch,
cramped but usable (on the watchOS 27.0 Simulator a calendar request from it
prompted and answered granted). The example's pubspec adds what it imports,
`baseflow_plugin_template` and `permission_handler_platform_interface`, and
`url_launcher_watchos` for the template's links, which call url_launcher only
when tapped; `res/images/` is upstream's. On the Simulator the template's
info page opened, but its link buttons sit below a scroll area too small to
reach there, so the links were not tapped. The Info.plist has the usage
description of each permission. Upstream has no integration test, so
`integration_test/permission_handler_test.dart` is this package's own; it
imports only `permission_handler`.

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
