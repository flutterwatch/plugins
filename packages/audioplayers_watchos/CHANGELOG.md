## 0.1.0

* The version moves from 0.0.1 to 0.1.0, so that a `^0.1.0` constraint
  admits later fixes; `^0.0.1` admits none.
* README: the install snippet names `audioplayers: ^6.8.1` and this version.
* `pubspec.yaml`: `repository` points at this package's folder in the plugins
  repo.
* Comments now say what keeps the FFI exports in the app: the CLI force-loads
  the plugin archive, each export is `used` with default visibility, and the
  CLI keeps global symbols through the App Store strip. `ffiSymbols` lists the
  exports.
* README: a "Not supported on watchOS" table; PORTING_REPORT: an "Interface
  coverage" list of every member of `audioplayers_platform_interface` 7.2.0,
  audited by hand.
* README: no longer says `AudioPlayer` works as on the other platforms; it
  points at the watch notes and the table.
* Example: `pubspec.yaml` names `audioplayers: ^6.8.1` instead of `any`.

## 0.0.1

* Initial watchOS implementation of `audioplayers` over dart:ffi —
  AVPlayer-backed playback with URL/bytes sources, seek, volume, rate,
  release modes, audio-context mapping, and the full `AudioEvent` stream.
* Ships the upstream example app and integration suites verbatim.
