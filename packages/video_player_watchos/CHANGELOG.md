## 0.0.1-beta.2

* Requires `flutter_watchos` ≥ 0.1.0-beta.9. flutter-watchos 0.1.0-beta.12
  composites platform views from the layer tree, and `flutter_watchos`
  0.1.0-beta.8 does not put one there: with it, playback and controls work but
  the video area stays black. 0.1.0-beta.9 also keeps working on older
  flutter-watchos releases.
* Docs describe the composited platform view: Flutter content painted after the
  video draws over it, `layer: belowFlutter` sends every touch to Flutter, and
  ancestor clips, opacity and transforms apply.

## 0.0.1-beta.1

* Initial watchOS implementation of `video_player`: AVFoundation playback
  over dart:ffi, rendered through a native AVKit platform view
  (requires flutter-watchos with platform-view support and
  `flutter_watchos` ≥ 0.1.0-beta.5). Published as a pre-release while its
  `flutter_watchos` dependency remains a pre-release.
