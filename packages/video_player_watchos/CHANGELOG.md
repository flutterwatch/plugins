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
