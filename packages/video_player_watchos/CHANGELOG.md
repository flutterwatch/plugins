## 0.1.1

* README: the install snippet names this version.
* `pubspec.yaml`: `repository` points at this package's folder in the plugins
  repo.
* Comments now say what keeps the FFI exports in the app: the CLI force-loads
  the plugin archive, each export is `used` with default visibility, and the
  CLI keeps global symbols through the App Store strip. `ffiSymbols` lists the
  exports.
* README: a "Not supported on watchOS" table; PORTING_REPORT: an "Interface
  coverage" list of every member of `video_player_platform_interface` 6.9.0,
  audited by hand.
* Example: `pubspec.yaml` names `video_player: ^2.14.0` and `path_provider:
  ^2.1.6` instead of `any`.

## 0.1.0

* For flutter-watchos 0.1.0: depends on `flutter_watchos` 0.1.0 or later.
  The code is the same as in the last published build.
* The watchOS implementation of `video_player`: playback on AVFoundation
  (`AVPlayer`) over dart:ffi, shown through a native AVKit (SwiftUI
  `VideoPlayer`) platform view.
* flutter-watchos composites the view in paint order: Flutter content painted
  after the video draws over it, `layer: belowFlutter` sends every touch to
  Flutter, and ancestor clips, opacity and transforms apply.
* Network, file and asset sources; play, pause, seek and position; volume,
  playback speed and looping; `setMixWithOthers`; audio track selection for
  HLS streams. Content URIs are not supported (they are Android only).
