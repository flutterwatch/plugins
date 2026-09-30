# audioplayers_watchos — porting report

Scaffolded by `flutter-watchos plugin port --from-pub audioplayers_darwin
--include-example` on 2026-07-16 (source: `audioplayers_darwin` 6.5.0,
base platform ios/Swift); the native backend and Dart implementation were
then written against `audioplayers_platform_interface` 7.x.

## Verification status

| Aspect | Result |
|---|---|
| Implementation | ✅ Working (FFI, AVPlayer) |
| watchOS capability | Partial — no balance, no low-latency player mode |
| Host unit tests (`flutter-watchos test`) | ✅ 13/13 pass |
| Upstream `lib_test.dart` | ✅ passes verbatim (15 + 4 platform-skipped, local fixture server) |
| Upstream `platform_test.dart` | ✅ passes verbatim (39) |
| Upstream `app_test.dart` | ✅ passes verbatim (3, content scale 0.5) |
| Simulator run, 29 September 2026 (watchOS 27.0) | ◐ `lib_test.dart`: 14 pass, 4 skipped, 1 fails ("test url source with special char" streams a remote file that now answers 404); `platform_test.dart` and `app_test.dart` not run |
| Internal unified demo | ✅ included |

Marking: ✅ full / passes · ◐ partial — reason given · ○ not applicable (no upstream test) · ✗ unsupported on watchOS.

## Status

✅ WORKING implementation:

- **Native** — `watchos/Classes/audioplayers_watchos_ffi.m` keeps one
  `AVPlayer` per string `playerId` in a lock-guarded registry and exports
  15 C symbols (create/dispose/source/resume/pause/stop/release/seek/
  volume/rate/release-mode/state/error/audio-context). KVO on the item
  `status` and player `timeControlStatus`, plus the play-to-end
  notification, keep a state snapshot whose one-shot occurrences
  (`prepared`, `seekComplete`, `complete`) are **edge counters**, so
  pulses shorter than a poll interval are never missed. Every AVPlayer
  mutation is marshaled to the main queue (repo threading rule); reads
  stay lock-guarded.
- **Release modes** are handled natively at play-to-end: `loop` seeks to
  zero and resumes without a complete event; `release` rewinds, emits
  complete, and unloads the item; `stop` rewinds and emits complete.
- **Dart** — `lib/audioplayers_watchos.dart` extends
  `AudioplayersPlatformInterface`, polls the snapshot (~100 ms) and diffs
  successive states into the `AudioEvent` stream; `registerWith()` also
  installs `GlobalAudioplayersWatchos` for the global interface.

## Interface coverage

Every public member of `audioplayers_platform_interface` 7.2.0
(`AudioplayersPlatformInterface` and `GlobalAudioplayersPlatformInterface`),
audited by hand against this package's code. The static `instance` is set by
`registerWith()`. ✅ implemented · ◐ implemented with a limit · ✗ throws or
fails on watchOS. The README's "Not supported on watchOS" table lists the ✗
rows.

| Member | watchOS |
|---|---|
| `create` / `dispose` | ✅ one native `AVPlayer` per player id |
| `setSourceUrl` | ✅ `AVPlayerItem`, remote URLs and local files |
| `setSourceBytes` | ✅ spooled to a temporary file and played from there; pass `mimeType` so the container is known |
| `resume` / `pause` / `stop` / `release` / `seek` | ✅ |
| `setVolume` / `setPlaybackRate` | ✅ |
| `setReleaseMode` | ✅ release, loop and stop, handled natively at the end of playback |
| `getDuration` / `getCurrentPosition` | ✅ null while unknown |
| `getEventStream` | ✅ prepared, duration, seek-complete, complete, log and error events |
| `emitLog` / `emitError` | ✅ |
| `setAudioContext` | ◐ the `AudioContextIOS` category and `mixWithOthers` / `duckOthers` map onto the watch `AVAudioSession`; iOS-only options such as `defaultToSpeaker` are ignored |
| `setBalance` | ✗ no effect: it emits a log event instead. `AVPlayer` has no per-channel balance (the iOS implementation does the same) |
| `setPlayerMode` | ✗ no effect: `lowLatency` plays as `mediaPlayer`. watchOS has no low-latency player |
| `GlobalAudioplayersPlatformInterface.init` / `emitGlobalLog` / `emitGlobalError` / `getGlobalEventStream` | ✅ |
| `GlobalAudioplayersPlatformInterface.setGlobalAudioContext` | ◐ the same mapping as `setAudioContext` |

## Platform notes

- The upstream example app, its official integration suites, and its
  `server/` fixture server ship verbatim; the example runner opts into
  `FlutterWatchOSContentScale` (0.5) because the upstream UI is
  phone-designed. The suites are run against the local server
  (`--dart-define=USE_LOCAL_SERVER=true`) like upstream CI — upstream's
  remote fixture host is missing files (e.g. the special-character wav),
  so only the local-server run is hermetic.
- `audioplayers`' asset support (`AudioCache`) uses `path_provider`, so
  the example depends on `path_provider_watchos` from this repo.
- On watchOS the platform reports `TargetPlatform.iOS`, so the upstream
  suites apply their iOS feature set (no bytes/dataUri/balance tests).
- Error contract matches upstream darwin, as asserted by
  `platform_test.dart`: source failures throw message
  `Failed to set source. …/troubleshooting.md` with the AVFoundation
  description in `details`; player-scoped calls on a disposed id throw
  `Player has not yet been created or has already been disposed.`
- Threading model: registry membership (create/dispose) and state
  publication (stop's position-0, release's unload) are synchronous on
  the calling FFI thread — the official suites assert their effects
  immediately after the call returns — while every AVPlayer mutation is
  marshaled to the main queue (repo threading rule).

---

FFI federated model — no dart:ffi native-assets, no Flutter patching.
