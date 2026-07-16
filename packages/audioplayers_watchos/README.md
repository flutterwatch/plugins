# audioplayers_watchos

The watchOS implementation of [`audioplayers`](https://pub.dev/packages/audioplayers).

Playback is driven by `AVPlayer` (AVFoundation) through dart:ffi — the
supported plugin model on watchOS. One native player is kept per
`playerId`; play/pause/seek/volume/rate/release-mode are applied natively,
and the event stream (`prepared`, `duration`, `seekComplete`, `complete`,
errors) is derived by polling a lock-guarded native state snapshot.

## Usage

This is a federated plugin implementation. Apps that already depend on `audioplayers` and target watchOS only need to add this package alongside it:

```yaml
dependencies:
  audioplayers: ^<latest>
  audioplayers_watchos: ^0.0.1
```

No other change — `AudioPlayer` and friends work as on the other platforms.
Asset sources go through `audioplayers`' own `AudioCache`, which uses
`path_provider`; add `path_provider_watchos` alongside it the same way.

## watchOS notes

- **Balance** (`setBalance`) is not supported — `AVPlayer` has no
  per-channel balance. Calls emit a log event instead of throwing, matching
  the upstream iOS behaviour.
- **Player mode** (`setPlayerMode`) is a no-op; watchOS has no
  low-latency `AVAudioPlayer` pool.
- **Audio context**: the `AudioContextIOS` category and the
  `mixWithOthers` / `duckOthers` options map onto the watch
  `AVAudioSession`. iOS-only options with no watchOS equivalent (e.g.
  `defaultToSpeaker`) are ignored — the watch routes output itself
  (Bluetooth headphones or speaker).
- **Bytes sources** (`setSourceBytes`) are spooled to a temporary file and
  played from there; pass `mimeType` so the container format is known.
- On a real watch, background/long-form playback is subject to the system
  audio-session policy; short UI sounds and foreground playback behave as
  on iOS.

## Example on the watch screen

The bundled example is the upstream `audioplayers` example, verbatim. It is
a phone-designed multi-tab UI, so its runner sets `FlutterWatchOSContentScale`
in `Info.plist` to render it scaled-to-fit on the watch. See the example
README for details.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
