# video_player_watchos — porting report

## Verification status

| Aspect | Result |
|---|---|
| Implementation | ✅ Working (FFI + native platform view) |
| watchOS capability | Partial — no content URIs (Android-only); AVKit draws its own chrome while paused (see below) |
| Host unit tests (`flutter-watchos test`) | ✅ pass |
| Upstream integration test | ✅ passes verbatim (`video_player_test.dart` on the watch simulator) |
| Internal unified demo | ✅ included |

Marking: ✅ full / passes · ◐ partial — reason given · ○ not applicable (no upstream test) · ✗ unsupported on watchOS.

Unlike the other packages in this repo, the upstream Apple implementation
(`video_player_avfoundation`) renders through an iOS **texture/platform
view**, which has no direct watchOS equivalent — this package was written by
hand against `video_player_platform_interface` using the plugin platform-view
model (`WatchPlatformView` + plugin-shipped SwiftUI sources) that
flutter-watchos provides.

## Status

✅ WORKING implementation, in three pieces:

- **Control + state** — `watchos/Classes/video_player_watchos_ffi.m` drives
  `AVPlayer` and exports C symbols for create/dispose/play/pause/seek/
  volume/speed/looping/position. KVO keeps a lock-guarded state snapshot
  (`status`, playing, buffering, buffered range, duration, size, completed
  count) that Dart polls — the repo's standard cache-and-poll pattern.
- **Rendering** — `watchos/Views/video_player_watchos_views.swift` registers
  a SwiftUI `VideoPlayer` (AVKit) factory for the `video_player_watchos`
  view type; the Dart `buildView` embeds it with
  `WatchPlatformView(layer: belowFlutter)`, so Flutter content stacked over
  the video (controls, overlays) draws on top and gestures stay in Dart.
- **Dart** — `lib/video_player_watchos.dart` extends
  `video_player_platform_interface`, derives the `VideoEvent` stream by
  diffing successive snapshots, and resolves symbols via
  `DynamicLibrary.process()`.

## Interface coverage

Every public member of `video_player_platform_interface` 6.9.0
(`VideoPlayerPlatform`), audited by hand against this package's code. The
static `instance` is set by `registerWith()`. ✅ implemented · ◐ implemented
with a limit · ✗ throws or fails on watchOS. The README's "Not supported on
watchOS" table lists the ✗ rows.

| Member | watchOS |
|---|---|
| `init` / `dispose` | ✅ |
| `create` / `createWithOptions` | ✅ network, file and asset sources through `AVPlayerItem` |
| `videoEventsFor` | ✅ initialized, completed, buffering and play-state events |
| `play` / `pause` / `seekTo` / `getPosition` | ✅ |
| `setVolume` / `setPlaybackSpeed` / `setLooping` | ✅ |
| `buildView` / `buildViewWithOptions` | ✅ a `WatchPlatformView` under the Flutter content |
| `setMixWithOthers` | ✅ `AVAudioSession` category options |
| `getAudioTracks` / `selectAudioTrack` / `isAudioTrackSupportAvailable` | ✅ audible media-selection groups: empty for a plain MP4, filled for HLS |
| `create` with a content URI | ✗ throws `UnsupportedError`: content URIs are an Android concept |
| `setAllowBackgroundPlayback` | ✗ throws `UnimplementedError` when called: not implemented |
| `setPreventsDisplaySleepDuringVideoPlayback` | ✗ no effect (the interface default): not implemented |
| `getVideoTracks` / `selectVideoTrack` | ✗ throw `UnimplementedError` when called; `isVideoTrackSupportAvailable` returns false, so `video_player` does not call them |
| `setWebOptions` | ✗ throws `UnimplementedError` when called: web only |

## Platform notes

- The video surface is composited by the watch host, not drawn into the
  Flutter scene, so snapshot-based tests do not capture video pixels. The
  engine places it in paint order with the layer tree's clips, opacity and
  transforms.
- flutter-watchos 0.1.0 or later and `flutter_watchos` 0.1.0 or later are
  required. On an app created by an older flutter-watchos, the plugin builds
  and controls playback, but the video surface does not appear
  (`WatchPlatformView.isSupported` reports it).

---

Written by hand against `video_player_platform_interface`. FFI federated
model — no dart:ffi native-assets, no Flutter patching.

## AVKit's paused chrome cannot be suppressed

While the player is paused, watchOS draws a *Done* button, remaining time, a
play glyph and a scrubber over the video, even though the app drives playback
from Dart. There is no supported way to remove it, confirmed against the
watchOS 26.5 SDK:

- SwiftUI's `VideoPlayer` is the platform's only video surface. watchOS AVKit
  exports no Objective-C classes at all (no `AVPlayerViewController`), and
  `AVPlayerLayer`, `AVPlayerItemVideoOutput`, `AVAssetImageGenerator` and
  `AVAssetReader` are each `API_UNAVAILABLE(watchos)` — so there is neither an
  alternative renderer nor any way to obtain decoded frames and draw the video
  through Flutter instead.
- `VideoPlayer`'s watchOS interface exposes no controls-hiding modifier, and
  the chrome tracks `timeControlStatus` rather than touch input:
  `.disabled(true)` + `.allowsHitTesting(false)` were measured on the
  simulator and produced a pixel-identical paused frame.

Options if an app cannot tolerate the chrome, both of which trade something
away and so are left to the app: keep the media playing (the chrome auto-hides
during playback), or have the plugin blank the native surface while paused so
Flutter can draw its own paused state — which loses the frozen video frame.
