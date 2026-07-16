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
| Host unit tests (`flutter-watchos test`) | ✅ 12/12 pass |
| Upstream integration tests | ◐ verification in progress on the watch simulator |
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

## API coverage

| Method | watchOS |
|---|---|
| `create` / `dispose` | ✅ |
| `setSourceUrl` (remote / `isLocal`) | ✅ `AVPlayerItem` |
| `setSourceBytes` | ✅ spooled to a temp file (`mimeType` → container hint) |
| `resume` / `pause` / `stop` / `release` / `seek` | ✅ |
| `setVolume` / `setPlaybackRate` | ✅ |
| `setReleaseMode` (release / loop / stop) | ✅ handled natively at play-to-end |
| `getDuration` / `getCurrentPosition` | ✅ (null while unknown; position reports the seek target while a seek is in flight) |
| `getEventStream` (prepared / duration / seekComplete / complete / log / error) | ✅ poll-derived |
| `setAudioContext` | ◐ `AudioContextIOS` category + `mixWithOthers`/`duckOthers` map to the watch `AVAudioSession`; iOS-only options (e.g. `defaultToSpeaker`) do not exist on watchOS and are ignored |
| `setBalance` | ✗ no per-channel balance on `AVPlayer` — emits a log event (upstream iOS behaviour) |
| `setPlayerMode` | ✗ no low-latency pool on watchOS — no-op |
| `getGlobalEventStream` / `emitGlobal*` | ✅ |

## Platform notes

- The upstream example app and its official integration suites ship
  verbatim; the example runner opts into `FlutterWatchOSContentScale`
  (0.5) because the upstream UI is phone-designed.
- `audioplayers`' asset support (`AudioCache`) uses `path_provider`, so
  the example depends on `path_provider_watchos` from this repo.
- On watchOS the platform reports `TargetPlatform.iOS`, so the upstream
  suites apply their iOS feature set (no bytes/dataUri/balance tests).

---

FFI federated model — no dart:ffi native-assets, no Flutter patching.
