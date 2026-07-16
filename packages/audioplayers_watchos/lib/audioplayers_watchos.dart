// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `audioplayers`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so this package
// follows the FFI plugin model: `watchos/Classes/audioplayers_watchos_ffi.m`
// drives AVFoundation (one AVPlayer per audioplayers player id) and this
// class resolves the symbols via `DynamicLibrary.process()`.
//
// Events are poll-derived (the repo's standard cache-and-poll pattern):
// native KVO keeps a per-player state snapshot current — one-shot
// occurrences (prepared, seek complete, play-to-end) are edge counters so
// nothing is missed between polls — and [getEventStream] diffs successive
// snapshots into `AudioEvent`s.

import 'dart:async';
import 'dart:ffi';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

/// Mirror of the native `AudioplayersWatchosState` struct (field order must
/// match `audioplayers_watchos_ffi.h` exactly).
final class _NativeState extends Struct {
  @Int32()
  external int status;
  @Int32()
  external int isPlaying;
  @Int32()
  external int preparedCount;
  @Int32()
  external int seekCompleteCount;
  @Int32()
  external int completeCount;
  @Int64()
  external int durationMs;
  @Int64()
  external int positionMs;
}

/// One polled snapshot of a native player's state.
class WatchosAudioState {
  /// Creates a snapshot; see the native header for field semantics.
  const WatchosAudioState({
    required this.status,
    required this.isPlaying,
    required this.preparedCount,
    required this.seekCompleteCount,
    required this.completeCount,
    required this.durationMs,
    required this.positionMs,
  });

  /// 0 idle/loading, 1 prepared (ready to play), 2 failed.
  final int status;

  /// Whether AVPlayer is actively playing.
  final bool isPlaying;

  /// Increments when a source becomes ready.
  final int preparedCount;

  /// Increments when an async seek lands.
  final int seekCompleteCount;

  /// Increments each play-to-end (non-loop).
  final int completeCount;

  /// Media duration in ms; -1 unknown / indefinite (live).
  final int durationMs;

  /// Current position in ms (the seek target while a seek is in flight).
  final int positionMs;
}

/// FFI bindings to the native audioplayers_watchos C functions.
///
/// Overridable for tests via [AudioplayersWatchos.bindingsOverride]; the
/// [AudioplayersWatchosBindings.forTesting] constructor skips FFI so fakes
/// work off-device.
class AudioplayersWatchosBindings {
  /// Creates bindings that look up native symbols in the current process.
  AudioplayersWatchosBindings() : _lib = DynamicLibrary.process();

  /// Constructor for fakes/mocks — skips FFI initialization.
  AudioplayersWatchosBindings.forTesting() : _lib = null;

  final DynamicLibrary? _lib;

  late final void Function(Pointer<Utf8>) _create = _lib!
      .lookupFunction<Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('audioplayers_watchos_create');

  late final void Function(Pointer<Utf8>) _dispose = _lib!
      .lookupFunction<Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('audioplayers_watchos_dispose');

  late final int Function(Pointer<Utf8>, Pointer<Utf8>, bool) _setSourceUrl =
      _lib!.lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Bool),
              int Function(Pointer<Utf8>, Pointer<Utf8>, bool)>(
          'audioplayers_watchos_set_source_url');

  late final int Function(Pointer<Utf8>, Pointer<Uint8>, int, Pointer<Utf8>)
      _setSourceBytes = _lib!.lookupFunction<
              Int32 Function(Pointer<Utf8>, Pointer<Uint8>, Int64, Pointer<Utf8>),
              int Function(Pointer<Utf8>, Pointer<Uint8>, int, Pointer<Utf8>)>(
          'audioplayers_watchos_set_source_bytes');

  late final void Function(Pointer<Utf8>) _resume = _lib!
      .lookupFunction<Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('audioplayers_watchos_resume');

  late final void Function(Pointer<Utf8>) _pause = _lib!
      .lookupFunction<Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('audioplayers_watchos_pause');

  late final void Function(Pointer<Utf8>) _stop = _lib!
      .lookupFunction<Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('audioplayers_watchos_stop');

  late final void Function(Pointer<Utf8>) _release = _lib!
      .lookupFunction<Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('audioplayers_watchos_release');

  late final void Function(Pointer<Utf8>, int) _seek = _lib!
      .lookupFunction<Void Function(Pointer<Utf8>, Int64),
          void Function(Pointer<Utf8>, int)>('audioplayers_watchos_seek');

  late final void Function(Pointer<Utf8>, double) _setVolume = _lib!
      .lookupFunction<Void Function(Pointer<Utf8>, Double),
              void Function(Pointer<Utf8>, double)>(
          'audioplayers_watchos_set_volume');

  late final void Function(Pointer<Utf8>, double) _setRate = _lib!
      .lookupFunction<Void Function(Pointer<Utf8>, Double),
          void Function(Pointer<Utf8>, double)>('audioplayers_watchos_set_rate');

  late final void Function(Pointer<Utf8>, int) _setReleaseMode = _lib!
      .lookupFunction<Void Function(Pointer<Utf8>, Int32),
              void Function(Pointer<Utf8>, int)>(
          'audioplayers_watchos_set_release_mode');

  late final bool Function(Pointer<Utf8>, Pointer<_NativeState>) _readState =
      _lib!.lookupFunction<Bool Function(Pointer<Utf8>, Pointer<_NativeState>),
              bool Function(Pointer<Utf8>, Pointer<_NativeState>)>(
          'audioplayers_watchos_read_state');

  late final Pointer<Utf8> Function(Pointer<Utf8>) _error = _lib!
      .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('audioplayers_watchos_error');

  late final int Function(Pointer<Utf8>, bool, bool) _setAudioContext = _lib!
      .lookupFunction<Int32 Function(Pointer<Utf8>, Bool, Bool),
              int Function(Pointer<Utf8>, bool, bool)>(
          'audioplayers_watchos_set_audio_context');

  /// Runs [body] with a native UTF-8 copy of [s], freeing it afterwards.
  T _withUtf8<T>(String s, T Function(Pointer<Utf8>) body) {
    final Pointer<Utf8> p = s.toNativeUtf8();
    try {
      return body(p);
    } finally {
      calloc.free(p);
    }
  }

  /// Creates the native player for [playerId] (idempotent).
  void create(String playerId) => _withUtf8(playerId, _create);

  /// Tears the native player down.
  void dispose(String playerId) => _withUtf8(playerId, _dispose);

  /// Loads a URL/path source; returns 0 on success.
  int setSourceUrl(String playerId, String url, bool isLocal) =>
      _withUtf8(playerId,
          (Pointer<Utf8> p) => _withUtf8(url, (Pointer<Utf8> u) => _setSourceUrl(p, u, isLocal)));

  /// Loads a bytes source (spooled to a temp file natively).
  int setSourceBytes(String playerId, Uint8List bytes, String extensionHint) {
    final Pointer<Uint8> data = calloc<Uint8>(bytes.length);
    data.asTypedList(bytes.length).setAll(0, bytes);
    try {
      return _withUtf8(
          playerId,
          (Pointer<Utf8> p) => _withUtf8(extensionHint,
              (Pointer<Utf8> e) => _setSourceBytes(p, data, bytes.length, e)));
    } finally {
      calloc.free(data);
    }
  }

  /// Starts (or resumes) playback at the requested rate.
  void resume(String playerId) => _withUtf8(playerId, _resume);

  /// Pauses playback, keeping the position.
  void pause(String playerId) => _withUtf8(playerId, _pause);

  /// Pauses and rewinds to zero, keeping the source.
  void stop(String playerId) => _withUtf8(playerId, _stop);

  /// Unloads the source.
  void release(String playerId) => _withUtf8(playerId, _release);

  /// Seeks to [positionMs] (async natively; an edge counter reports landing).
  void seek(String playerId, int positionMs) =>
      _withUtf8(playerId, (Pointer<Utf8> p) => _seek(p, positionMs));

  /// Sets the volume (0.0–1.0).
  void setVolume(String playerId, double volume) =>
      _withUtf8(playerId, (Pointer<Utf8> p) => _setVolume(p, volume));

  /// Sets the playback rate.
  void setRate(String playerId, double rate) =>
      _withUtf8(playerId, (Pointer<Utf8> p) => _setRate(p, rate));

  /// Sets the release mode (ReleaseMode.index).
  void setReleaseMode(String playerId, int mode) =>
      _withUtf8(playerId, (Pointer<Utf8> p) => _setReleaseMode(p, mode));

  /// Copies the player's current state snapshot; null for unknown ids.
  WatchosAudioState? readState(String playerId) {
    final Pointer<_NativeState> out = calloc<_NativeState>();
    try {
      final bool ok =
          _withUtf8(playerId, (Pointer<Utf8> p) => _readState(p, out));
      if (!ok) {
        return null;
      }
      final _NativeState s = out.ref;
      return WatchosAudioState(
        status: s.status,
        isPlaying: s.isPlaying != 0,
        preparedCount: s.preparedCount,
        seekCompleteCount: s.seekCompleteCount,
        completeCount: s.completeCount,
        durationMs: s.durationMs,
        positionMs: s.positionMs,
      );
    } finally {
      calloc.free(out);
    }
  }

  /// Failure description once `status == 2`; empty otherwise.
  String error(String playerId) =>
      _withUtf8(playerId, (Pointer<Utf8> p) => _error(p).toDartString());

  /// Applies the AVAudioSession category/options (session-wide).
  int setAudioContext(String category, bool mixWithOthers, bool duckOthers) =>
      _withUtf8(category,
          (Pointer<Utf8> c) => _setAudioContext(c, mixWithOthers, duckOthers));
}

/// Per-player poll loop state for [AudioplayersWatchos.getEventStream].
class _PlayerEvents {
  _PlayerEvents(this.playerId, this.bindings);

  final String playerId;
  final AudioplayersWatchosBindings bindings;
  late final StreamController<AudioEvent> controller =
      StreamController<AudioEvent>.broadcast(
    onListen: _start,
    onCancel: _stopPolling,
  );

  Timer? _timer;
  WatchosAudioState? _last;
  bool _errorSent = false;

  void _start() {
    _tick();
    _timer = Timer.periodic(AudioplayersWatchos.pollInterval, (_) => _tick());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    final WatchosAudioState? state = bindings.readState(playerId);
    if (state == null) {
      return; // Disposed (or not yet created) — nothing to report.
    }
    if (state.status == 2) {
      if (!_errorSent) {
        _errorSent = true;
        controller.addError(PlatformException(
            code: 'WatchosAudioError', message: bindings.error(playerId)));
      }
      _last = state;
      return;
    }
    _errorSent = false;
    final WatchosAudioState? previous = _last;
    _last = state;
    if (previous == null) {
      return;
    }
    if (state.preparedCount > previous.preparedCount) {
      controller.add(const AudioEvent(
          eventType: AudioEventType.prepared, isPrepared: true));
      if (state.durationMs >= 0) {
        controller.add(AudioEvent(
          eventType: AudioEventType.duration,
          duration: Duration(milliseconds: state.durationMs),
        ));
      }
    }
    for (int i = previous.seekCompleteCount;
        i < state.seekCompleteCount;
        i++) {
      controller.add(const AudioEvent(eventType: AudioEventType.seekComplete));
    }
    for (int i = previous.completeCount; i < state.completeCount; i++) {
      controller.add(const AudioEvent(eventType: AudioEventType.complete));
    }
  }

  void close() {
    _stopPolling();
    controller.close();
  }
}

/// watchOS implementation of [AudioplayersPlatformInterface].
class AudioplayersWatchos extends AudioplayersPlatformInterface {
  /// Test hook: set before first use to replace the FFI bindings.
  static AudioplayersWatchosBindings? bindingsOverride;

  static AudioplayersWatchosBindings? _bindings;

  static AudioplayersWatchosBindings get _b =>
      bindingsOverride ?? (_bindings ??= AudioplayersWatchosBindings());

  /// How often [getEventStream] polls the native state snapshot.
  static Duration pollInterval = const Duration(milliseconds: 100);

  final Map<String, _PlayerEvents> _events = <String, _PlayerEvents>{};

  /// Registers this implementation as the default `audioplayers` platform
  /// implementation on watchOS.
  static void registerWith() {
    AudioplayersPlatformInterface.instance = AudioplayersWatchos();
    GlobalAudioplayersPlatformInterface.instance =
        GlobalAudioplayersWatchos();
  }

  _PlayerEvents _eventsFor(String playerId) => _events.putIfAbsent(
      playerId, () => _PlayerEvents(playerId, _b));

  @override
  Future<void> create(String playerId) async {
    _b.create(playerId);
    _eventsFor(playerId);
  }

  @override
  Future<void> dispose(String playerId) async {
    _b.dispose(playerId);
    _events.remove(playerId)?.close();
  }

  @override
  Future<void> resume(String playerId) async => _b.resume(playerId);

  @override
  Future<void> pause(String playerId) async => _b.pause(playerId);

  @override
  Future<void> stop(String playerId) async => _b.stop(playerId);

  @override
  Future<void> release(String playerId) async => _b.release(playerId);

  @override
  Future<void> seek(String playerId, Duration position) async =>
      _b.seek(playerId, position.inMilliseconds);

  @override
  Future<void> setBalance(String playerId, double balance) async {
    // AVPlayer has no per-channel balance (same as upstream iOS/macOS).
    _eventsFor(playerId).controller.add(const AudioEvent(
          eventType: AudioEventType.log,
          logMessage: 'setBalance is not supported on watchOS',
        ));
  }

  @override
  Future<void> setVolume(String playerId, double volume) async =>
      _b.setVolume(playerId, volume);

  @override
  Future<void> setReleaseMode(
          String playerId, ReleaseMode releaseMode) async =>
      _b.setReleaseMode(playerId, releaseMode.index);

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async =>
      _b.setRate(playerId, playbackRate);

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    final int status = _b.setSourceUrl(playerId, url, isLocal ?? false);
    if (status != 0) {
      throw PlatformException(
          code: 'WatchosAudioError', message: 'Invalid source url: $url');
    }
  }

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    final int status =
        _b.setSourceBytes(playerId, bytes, _extensionForMime(mimeType));
    if (status != 0) {
      throw PlatformException(
          code: 'WatchosAudioError', message: 'Could not load bytes source');
    }
  }

  static String _extensionForMime(String? mimeType) {
    switch (mimeType) {
      case 'audio/mpeg':
        return 'mp3';
      case 'audio/wav':
      case 'audio/x-wav':
        return 'wav';
      case 'audio/aac':
        return 'aac';
      case 'audio/mp4':
        return 'm4a';
      default:
        return 'mp3'; // AVFoundation sniffs content; the name is a hint.
    }
  }

  @override
  Future<void> setAudioContext(
      String playerId, AudioContext audioContext) async {
    _applyContext(_b, audioContext);
  }

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {
    // Only one backend exists on watchOS (AVPlayer); lowLatency is accepted
    // and treated as mediaPlayer, matching upstream darwin.
  }

  @override
  Future<int?> getDuration(String playerId) async {
    final WatchosAudioState? state = _b.readState(playerId);
    if (state == null || state.durationMs < 0) {
      return null;
    }
    return state.durationMs;
  }

  @override
  Future<int?> getCurrentPosition(String playerId) async {
    final WatchosAudioState? state = _b.readState(playerId);
    if (state == null || state.status != 1) {
      return null;
    }
    return state.positionMs;
  }

  @override
  Stream<AudioEvent> getEventStream(String playerId) =>
      _eventsFor(playerId).controller.stream;

  @override
  Future<void> emitLog(String playerId, String message) async {
    _eventsFor(playerId).controller.add(
        AudioEvent(eventType: AudioEventType.log, logMessage: message));
  }

  @override
  Future<void> emitError(String playerId, String code, String message) async {
    _eventsFor(playerId)
        .controller
        .addError(PlatformException(code: code, message: message));
  }

  /// Shared by the per-player and global interfaces.
  static void _applyContext(
      AudioplayersWatchosBindings bindings, AudioContext audioContext) {
    final AudioContextIOS ios = audioContext.iOS;
    bindings.setAudioContext(
      ios.category.name,
      ios.options.contains(AVAudioSessionOptions.mixWithOthers),
      ios.options.contains(AVAudioSessionOptions.duckOthers),
    );
  }
}

/// watchOS implementation of [GlobalAudioplayersPlatformInterface].
class GlobalAudioplayersWatchos extends GlobalAudioplayersPlatformInterface {
  final StreamController<GlobalAudioEvent> _globalEvents =
      StreamController<GlobalAudioEvent>.broadcast();

  @override
  Future<void> init() async {
    // Players are created on demand; nothing global to prime.
  }

  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {
    AudioplayersWatchos._applyContext(AudioplayersWatchos._b, ctx);
  }

  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => _globalEvents.stream;

  @override
  Future<void> emitGlobalLog(String message) async {
    _globalEvents.add(GlobalAudioEvent(
        eventType: GlobalAudioEventType.log, logMessage: message));
  }

  @override
  Future<void> emitGlobalError(String code, String message) async {
    _globalEvents.addError(PlatformException(code: code, message: message));
  }
}
