## 0.2.0

**Breaking**

* `GeolocatorWatchosBackend`, the public seam tests fake, changed shape:
  `requestLocation` takes the accuracy index; `stopLocationRequest`,
  `positionCount`, `accuracyAuthorization`, `requestTemporaryFullAccuracy`
  and `accuracyRequestsDone` are new; `startUpdates` takes `activityType` and
  `allowBackground`. The native callback now carries a
  `GeolocatorWatchosSignal` kind.
* `getPositionStream` called while a stream runs returns that stream, with
  the settings it started with, as geolocator_apple does. A second stream
  with other settings used to replace the first one's.

**Added**

* `getLocationAccuracy` reports `accuracyAuthorization`: precise or reduced.
* `requestTemporaryFullAccuracy` asks for full accuracy with a purpose key and
  waits for the answer. Without `NSLocationTemporaryUsageDescriptionDictionary`
  in the `Info.plist` it throws `PermissionDefinitionsNotFoundException`, as
  geolocator does on iOS.
* `getServiceStatusStream` starts with the current status, then reports each
  change CoreLocation signals. It reads the services switch only when
  CoreLocation reports an authorization change, not on every fix.
* `AppleSettings` passed to `getPositionStream` now reach CoreLocation, read
  through `toJson()`: `activityType` (for example `ActivityType.fitness` for
  a run) and `allowBackgroundLocationUpdates`, which `AppleSettings` turns on
  by default. Background updates turn on only when the `Info.plist`'s
  `UIBackgroundModes` has `location`, because CoreLocation asserts otherwise;
  `location` under `WKBackgroundModes` does not count (checked on the
  watchOS 27.0 Simulator). A stream without `AppleSettings` gets
  `CLActivityTypeOther`, not the previous stream's type.
  `ActivityType.maritime` is `CLActivityTypeMaritime` when built with the
  watchOS 27 SDK and run on watchOS 27, and `CLActivityTypeOtherNavigation`
  otherwise, as in geolocator_apple; the package still builds with Xcode 26.
* Five FFI exports: `geolocator_watchos_accuracy_authorization`,
  `_request_temporary_full_accuracy`, `_accuracy_requests_done`,
  `_stop_location_request` and `_position_count`.
  `geolocator_watchos_start_updates` takes the activity type and the
  background flag, and `geolocator_watchos_request_location` the accuracy.

**Fixed**

* `getCurrentPosition` has a `CLLocationManager` of its own, as in
  geolocator_apple, so it no longer waits on a running stream's distance
  filter, which timed it out when the wearer stood still, nor stops or
  reconfigures the stream. It skips cached fixes more than 5 seconds old,
  which CoreLocation hands over first; a running stream's next fix answers
  it too.
* A position stream emits every fix CoreLocation delivers, with no age
  filter, as geolocator_apple's does: a reduced-accuracy fix can
  legitimately be old.

**Docs**

* README and PORTING_REPORT: the three members move out of "Not supported on
  watchOS"; a section on workouts and background updates, with App Review
  guideline 2.5.4, and what is not yet checked on a physical watch.
* Comments no longer say that Dart polls the cached fix: the delegate wakes
  Dart.

## 0.1.1

* README: the install snippet names `geolocator: ^14.1.1` and this version.
  It named `^0.0.1`, which does not admit 0.1.x.
* `pubspec.yaml`: `repository` points at this package's folder in the plugins
  repo.
* Comments now say what keeps the FFI exports in the app: the CLI force-loads
  the plugin archive, each export is `used` with default visibility, and the
  CLI keeps global symbols through the App Store strip. `ffiSymbols` lists the
  exports.
* README: a "Not supported on watchOS" table; PORTING_REPORT: an "Interface
  coverage" list of every member of `geolocator_platform_interface` 4.4.0,
  audited by hand.
* Dartdoc on every public member, and `public_member_api_docs` is on in
  `analysis_options.yaml`.
* Example: `pubspec.yaml` names `geolocator: ^14.1.1` instead of `any`.

## 0.1.0

First release beyond the generated scaffold.

**Breaking**

* `pollInterval` is gone, replaced by `permissionTimeout` (default 2 minutes),
  which bounds the wait for the system permission prompt rather than setting a
  polling rate.
* Minimum Dart SDK is now 3.1.0, where `NativeCallable.listener` landed.

**Changed**

* `getPositionStream`, `getCurrentPosition` and `requestPermission` are all
  **pushed** from CoreLocation delegate callbacks. No polling remains.
* Added a `locationManagerDidChangeAuthorization:` delegate method: the answer
  to a permission prompt arrives there and nowhere else, so waiting on it is
  the only way to observe it without polling.
* `didFailWithError` now wakes a waiter, which re-checks rather than sitting
  until its deadline.

**Fixed**

* The three callers that can wait concurrently — a position stream, a pending
  `getCurrentPosition`, a pending `requestPermission` — now share one native
  callback. The native side holds a single callback pointer, so registering
  per caller let whichever finished first silence the others.
* The shared `NativeCallable` is now reused across listen/cancel cycles instead
  of being discarded when the last waiter left. A `NativeCallable` is only
  reclaimed by `close()`, which is exactly what cannot be called while native
  might be between reading the pointer and calling it — so the old code leaked
  one trampoline per cycle for the life of the app. Only the pointer is
  unregistered now.

## 0.0.1

* Initial watchOS FFI scaffold generated by `flutter-watchos plugin port`
  from `geolocator_apple`.
