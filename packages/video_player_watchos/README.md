# video_player_watchos

The watchOS implementation of [`video_player`](https://pub.dev/packages/video_player).

Playback runs on **AVFoundation** (`AVPlayer`) over dart:ffi; rendering is a
**native platform view** — the plugin ships a SwiftUI `VideoPlayer` (AVKit)
surface that the app runner composites *under* the Flutter frame, so Flutter
content (controls, progress overlays) draws over the video and gestures stay
in Dart, matching upstream's texture semantics. `VideoEvent`s are derived by
polling a natively cached state snapshot.

> Requires a flutter-watchos with platform-view support and
> `flutter_watchos` ≥ 0.1.0-beta.5.

## Usage

This is a federated plugin implementation. Apps that already depend on
`video_player` and target watchOS only need to add this package alongside it:

```yaml
dependencies:
  video_player: ^<latest>
  video_player_watchos: ^0.0.1
```

The plugin registers automatically via Flutter's federated registry — no
explicit imports required from app code.

## Behaviour on watchOS

| Feature | watchOS |
|---|---|
| Network / file / asset sources | supported (`AVPlayer`; HLS included) |
| Play, pause, seek, position, duration | supported |
| Volume, playback speed, looping | supported |
| `VideoPlayer` widget rendering | supported (native AVKit surface in the underlay layer) |
| Buffering / play-state / completed events | supported (poll-derived) |
| `setMixWithOthers` | supported (`AVAudioSession`) |
| Content URIs | not supported (Android-only concept) |
| Audio track selection (`getAudioTracks` / `selectAudioTrack`) | supported via `AVMediaCharacteristicAudible` selection groups — empty for regular MP4s, populated for HLS streams (same as the upstream Apple impl) |
| Subtitles/captions rendering | as upstream: `ClosedCaptionFile` is Dart-side and works; embedded-track selection is not implemented |

Because the video surface is composited by the watch host rather than drawn
into the Flutter scene, two platform constraints apply: the video rect is
axis-aligned (no `Transform` rotations of the video itself), and widgets that
rely on snapshotting the scene (e.g. screenshot-based golden tests) capture
the UI hole, not the video pixels.

### Paused playback shows AVKit's controls

While the video is **paused**, watchOS draws its own playback chrome over the
video surface — a *Done* button, the remaining time, a play glyph and a
scrubber — even when your app drives playback entirely from Dart. This is a
platform limitation, not a plugin choice, and there is currently no way to
turn it off:

- SwiftUI's `VideoPlayer` is the *only* video surface watchOS offers. watchOS
  AVKit exports no `AVPlayerViewController` (it has no Objective-C classes at
  all), and `AVPlayerLayer`, `AVPlayerItemVideoOutput`,
  `AVAssetImageGenerator` and `AVAssetReader` are all
  `API_UNAVAILABLE(watchos)` — so there is no alternative renderer and no way
  to obtain decoded frames to draw the video yourself.
- `VideoPlayer` exposes no controls-hiding modifier on watchOS, and the chrome
  follows the player's `timeControlStatus`, so `.disabled(true)` and
  `.allowsHitTesting(false)` do not suppress it (verified on-device-class
  simulator).

The chrome auto-hides again as soon as playback resumes, so it only affects
the paused state.

> **Simulator note:** simulators play video without sound routing
> peculiarities; on a physical Apple Watch, audio follows the system's audio
> route (Bluetooth headphones or the built-in speaker, per watchOS rules).

## Status

| Platform | Implemented |
|----------|-------------|
| Apple Watch (`watchos`) | yes |
| Watch simulator (`watchsimulator`) | yes |

## Example on the watch screen

The package ships the **upstream example app and its official integration
tests verbatim**. The upstream UI is phone-designed (nested tab bars), so
the example's runner opts into the flutter-watchos content scale
(`watchos/Runner/Info.plist`):

```xml
<key>FlutterWatchOSContentScale</key>
<real>0.6</real>
```

This lays the app out in a proportionally larger logical space rendered
smaller — same layout, smaller components — without touching the example's
Dart code.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
