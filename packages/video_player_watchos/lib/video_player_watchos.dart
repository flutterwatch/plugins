// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `video_player`, implemented over dart:ffi plus a
// native platform view.
//
// Method-channel plugins are not supported on watchOS, so this package
// follows the FFI plugin model: `watchos/Classes/video_player_watchos_ffi.m`
// drives AVFoundation (AVPlayer) and this class resolves the symbols via
// `DynamicLibrary.process()`. Rendering is a `WatchPlatformView`
// (package:flutter_watchos): the plugin's Swift side overlays AVKit's SwiftUI
// `VideoPlayer` in the UNDERLAY layer, so Flutter content (controls,
// progress overlays) draws over the video and gestures stay in Dart — the
// same contract as upstream's texture-based rendering.
//
// Events are poll-derived (the repo's standard cache-and-poll pattern):
// native KVO keeps a state snapshot current, and [videoEventsFor] diffs
// successive snapshots into `VideoEvent`s.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size; // dart:ffi's Size clashes with dart:ui's.

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Mirror of the native `VideoPlayerWatchosState` struct (field order must
/// match `video_player_watchos_ffi.h` exactly).
final class _NativeState extends Struct {
  @Int32()
  external int status;
  @Int32()
  external int isPlaying;
  @Int32()
  external int bufferingStartCount;
  @Int32()
  external int bufferingEndCount;
  @Int32()
  external int completedCount;
  @Int64()
  external int durationMs;
  @Int64()
  external int bufferedMs;
  @Double()
  external double width;
  @Double()
  external double height;
}

/// One polled snapshot of a native player's state.
class WatchosVideoState {
  /// Creates a snapshot; see the native header for field semantics.
  const WatchosVideoState({
    required this.status,
    required this.isPlaying,
    required this.bufferingStartCount,
    required this.bufferingEndCount,
    required this.completedCount,
    required this.durationMs,
    required this.bufferedMs,
    required this.width,
    required this.height,
  });

  /// 0 unknown, 1 initialized (ready to play), 2 failed.
  final int status;

  /// Whether AVPlayer is actively playing.
  final bool isPlaying;

  /// Increments each time playback stalls waiting for the buffer.
  final int bufferingStartCount;

  /// Increments each time playback can keep up again.
  final int bufferingEndCount;

  /// Increments each time playback reaches the end (non-looping).
  final int completedCount;

  /// Media duration in ms; -1 until known, 0 for indefinite (live).
  final int durationMs;

  /// End of the furthest contiguous buffered range, in ms.
  final int bufferedMs;

  /// Video dimensions in points (0 until ready / for audio-only media).
  final double width;

  /// Video dimensions in points (0 until ready / for audio-only media).
  final double height;
}

/// FFI bindings to the native video_player_watchos C functions.
///
/// Overridable for tests via [VideoPlayerWatchos.bindingsOverride]; the
/// [VideoPlayerWatchosBindings.forTesting] constructor skips FFI so fakes
/// work off-device.
class VideoPlayerWatchosBindings {
  /// Creates bindings that look up native symbols in the current process.
  VideoPlayerWatchosBindings() : _lib = DynamicLibrary.process();

  /// Constructor for fakes/mocks — skips FFI initialization.
  VideoPlayerWatchosBindings.forTesting() : _lib = null;

  final DynamicLibrary? _lib;

  late final int Function(Pointer<Utf8>, int) _create = _lib!
      .lookupFunction<Int64 Function(Pointer<Utf8>, Int32),
          int Function(Pointer<Utf8>, int)>('video_player_watchos_create');

  late final void Function(int) _dispose = _lib!
      .lookupFunction<Void Function(Int64), void Function(int)>(
          'video_player_watchos_dispose');

  late final void Function(int) _play = _lib!
      .lookupFunction<Void Function(Int64), void Function(int)>(
          'video_player_watchos_play');

  late final void Function(int) _pause = _lib!
      .lookupFunction<Void Function(Int64), void Function(int)>(
          'video_player_watchos_pause');

  late final void Function(int, double) _setVolume = _lib!
      .lookupFunction<Void Function(Int64, Double), void Function(int, double)>(
          'video_player_watchos_set_volume');

  late final void Function(int, bool) _setLooping = _lib!
      .lookupFunction<Void Function(Int64, Bool), void Function(int, bool)>(
          'video_player_watchos_set_looping');

  late final void Function(int, double) _setSpeed = _lib!
      .lookupFunction<Void Function(Int64, Double), void Function(int, double)>(
          'video_player_watchos_set_speed');

  late final void Function(int, int) _seek = _lib!
      .lookupFunction<Void Function(Int64, Int64), void Function(int, int)>(
          'video_player_watchos_seek');

  late final int Function(int) _position = _lib!
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
          'video_player_watchos_position');

  late final bool Function(int, Pointer<_NativeState>) _readState = _lib!
      .lookupFunction<Bool Function(Int64, Pointer<_NativeState>),
              bool Function(int, Pointer<_NativeState>)>(
          'video_player_watchos_read_state');

  late final Pointer<Utf8> Function(int) _error = _lib!
      .lookupFunction<Pointer<Utf8> Function(Int64), Pointer<Utf8> Function(int)>(
          'video_player_watchos_error');

  late final void Function(bool) _setMixWithOthers = _lib!
      .lookupFunction<Void Function(Bool), void Function(bool)>(
          'video_player_watchos_set_mix_with_others');

  late final Pointer<Utf8> Function(int) _getAudioTracks = _lib!
      .lookupFunction<Pointer<Utf8> Function(Int64), Pointer<Utf8> Function(int)>(
          'video_player_watchos_get_audio_tracks');

  late final bool Function(int, Pointer<Utf8>) _selectAudioTrack = _lib!
      .lookupFunction<Bool Function(Int64, Pointer<Utf8>),
              bool Function(int, Pointer<Utf8>)>(
          'video_player_watchos_select_audio_track');

  late final void Function() _registerViews = _lib!
      .lookupFunction<Void Function(), void Function()>(
          'video_player_watchos_register_views');

  /// Creates a native player; `sourceType`: 0 network, 1 file, 2 asset key.
  /// Returns the player id, or a negative value on invalid input.
  int create(String uri, int sourceType) {
    final Pointer<Utf8> cUri = uri.toNativeUtf8();
    try {
      return _create(cUri, sourceType);
    } finally {
      calloc.free(cUri);
    }
  }

  /// Tears the native player down.
  void dispose(int playerId) => _dispose(playerId);

  /// Starts (or resumes) playback at the requested speed.
  void play(int playerId) => _play(playerId);

  /// Pauses playback.
  void pause(int playerId) => _pause(playerId);

  /// Sets the volume (0.0–1.0).
  void setVolume(int playerId, double volume) => _setVolume(playerId, volume);

  /// Loops back to the start on play-to-end instead of completing.
  void setLooping(int playerId, bool looping) => _setLooping(playerId, looping);

  /// Sets the playback speed.
  void setSpeed(int playerId, double speed) => _setSpeed(playerId, speed);

  /// Seeks to `positionMs` (frame-accurate, async natively).
  void seek(int playerId, int positionMs) => _seek(playerId, positionMs);

  /// Current position in ms (the seek target while a seek is in flight).
  int position(int playerId) => _position(playerId);

  /// Copies the player's current state snapshot; null for unknown ids.
  WatchosVideoState? readState(int playerId) {
    final Pointer<_NativeState> out = calloc<_NativeState>();
    try {
      if (!_readState(playerId, out)) {
        return null;
      }
      final _NativeState s = out.ref;
      return WatchosVideoState(
        status: s.status,
        isPlaying: s.isPlaying != 0,
        bufferingStartCount: s.bufferingStartCount,
        bufferingEndCount: s.bufferingEndCount,
        completedCount: s.completedCount,
        durationMs: s.durationMs,
        bufferedMs: s.bufferedMs,
        width: s.width,
        height: s.height,
      );
    } finally {
      calloc.free(out);
    }
  }

  /// Failure description once `status == 2`; empty otherwise.
  String error(int playerId) => _error(playerId).toDartString();

  /// Mixes this app's audio with other audio instead of interrupting it.
  void setMixWithOthers(bool mix) => _setMixWithOthers(mix);

  /// The selectable audio tracks as a JSON array string (empty `[]` when the
  /// video has no audible media-selection group, e.g. a regular MP4).
  String audioTracksJson(int playerId) =>
      _getAudioTracks(playerId).toDartString();

  /// Selects an audio track by id; false if it couldn't be applied.
  bool selectAudioTrack(int playerId, String trackId) {
    final Pointer<Utf8> cId = trackId.toNativeUtf8();
    try {
      return _selectAudioTrack(playerId, cId);
    } finally {
      calloc.free(cId);
    }
  }

  /// Registers the plugin's native SwiftUI view factory with the app runner.
  void registerViews() => _registerViews();
}

/// watchOS implementation of [VideoPlayerPlatform].
class VideoPlayerWatchos extends VideoPlayerPlatform {
  /// Test hook: set before first use to replace the FFI bindings.
  static VideoPlayerWatchosBindings? bindingsOverride;

  static VideoPlayerWatchosBindings? _bindings;

  static VideoPlayerWatchosBindings get _b =>
      bindingsOverride ?? (_bindings ??= VideoPlayerWatchosBindings());

  /// How often [videoEventsFor] polls the native state snapshot.
  static Duration pollInterval = const Duration(milliseconds: 100);

  /// The platform-view type the plugin's native side registers.
  static const String viewType = 'video_player_watchos';

  /// Registers this implementation as the default `video_player` platform
  /// implementation on watchOS, and registers the native view factory with
  /// the app runner.
  static void registerWith() {
    VideoPlayerPlatform.instance = VideoPlayerWatchos();
    _b.registerViews();
  }

  @override
  Future<void> init() async {
    // Players are independent natively; nothing to prime.
  }

  @override
  Future<void> dispose(int playerId) async {
    _b.dispose(playerId);
  }

  @override
  Future<int?> create(DataSource dataSource) async {
    final String uri;
    final int sourceType;
    switch (dataSource.sourceType) {
      case DataSourceType.network:
        uri = dataSource.uri!;
        sourceType = 0;
      case DataSourceType.file:
        final String raw = dataSource.uri!;
        uri = raw.startsWith('file://') ? Uri.parse(raw).toFilePath() : raw;
        sourceType = 1;
      case DataSourceType.asset:
        final String? asset = dataSource.asset;
        uri = dataSource.package == null
            ? asset!
            : 'packages/${dataSource.package}/$asset';
        sourceType = 2;
      case DataSourceType.contentUri:
        throw UnsupportedError(
            'video_player_watchos: content URIs are Android-only');
    }
    final int playerId = _b.create(uri, sourceType);
    if (playerId < 0) {
      throw PlatformException(
          code: 'VideoError', message: 'Invalid video source: $uri');
    }
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    // Diff successive native snapshots into events. Polling runs only while
    // listened to, and stops for good once the player fails.
    late final StreamController<VideoEvent> controller;
    Timer? timer;
    bool initializedSent = false;
    bool errorSent = false;
    WatchosVideoState? last;

    void tick() {
      final WatchosVideoState? state = _b.readState(playerId);
      if (state == null) {
        return; // Disposed (or not yet created) — nothing to report.
      }
      if (state.status == 2) {
        if (!errorSent) {
          errorSent = true;
          controller.addError(PlatformException(
              code: 'VideoError', message: _b.error(playerId)));
          timer?.cancel();
          timer = null;
        }
        return;
      }
      if (!initializedSent && state.status == 1) {
        initializedSent = true;
        controller.add(VideoEvent(
          eventType: VideoEventType.initialized,
          duration: Duration(milliseconds: state.durationMs < 0 ? 0 : state.durationMs),
          size: Size(state.width, state.height),
          rotationCorrection: 0,
        ));
      }
      final WatchosVideoState? previous = last;
      last = state;
      if (previous == null) {
        return;
      }
      if (state.completedCount > previous.completedCount) {
        controller.add(VideoEvent(eventType: VideoEventType.completed));
      }
      // Replay buffering edges from the native counters (interleaved
      // start/end, starts first) so stalls shorter than one poll interval
      // are still reported.
      final int starts = state.bufferingStartCount - previous.bufferingStartCount;
      final int ends = state.bufferingEndCount - previous.bufferingEndCount;
      for (int i = 0; i < starts || i < ends; i++) {
        if (i < starts) {
          controller.add(VideoEvent(eventType: VideoEventType.bufferingStart));
        }
        if (i < ends) {
          controller.add(VideoEvent(eventType: VideoEventType.bufferingEnd));
        }
      }
      if (state.bufferedMs != previous.bufferedMs) {
        controller.add(VideoEvent(
          eventType: VideoEventType.bufferingUpdate,
          buffered: <DurationRange>[
            DurationRange(
                Duration.zero, Duration(milliseconds: state.bufferedMs)),
          ],
        ));
      }
      if (state.isPlaying != previous.isPlaying) {
        controller.add(VideoEvent(
          eventType: VideoEventType.isPlayingStateUpdate,
          isPlaying: state.isPlaying,
        ));
      }
    }

    controller = StreamController<VideoEvent>.broadcast(
      onListen: () {
        tick();
        timer = Timer.periodic(pollInterval, (_) => tick());
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );
    return controller.stream;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    _b.setLooping(playerId, looping);
  }

  @override
  Future<void> play(int playerId) async {
    _b.play(playerId);
  }

  @override
  Future<void> pause(int playerId) async {
    _b.pause(playerId);
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {
    _b.setVolume(playerId, volume);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    _b.setSpeed(playerId, speed);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    _b.seek(playerId, position.inMilliseconds);
  }

  @override
  Future<Duration> getPosition(int playerId) async {
    return Duration(milliseconds: _b.position(playerId));
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) {
    return buildView(options.playerId);
  }

  @override
  Widget buildView(int playerId) {
    // Underlay layer: the native AVKit surface sits UNDER the Flutter frame
    // (the widget punches a transparent hole), so Flutter content stacked
    // over the video — controls, progress overlays — draws on top and
    // gestures are handled in Dart, matching upstream's texture semantics.
    return WatchPlatformView(
      viewType: viewType,
      creationParams: '$playerId',
      layer: WatchPlatformViewLayer.belowFlutter,
    );
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    _b.setMixWithOthers(mixWithOthers);
  }

  @override
  bool isAudioTrackSupportAvailable() => true;

  @override
  Future<List<VideoAudioTrack>> getAudioTracks(int playerId) async {
    // AVFoundation exposes selectable audio only through a media-selection
    // group (HLS); a regular MP4 has none and returns an empty list — same as
    // the upstream Apple implementation.
    Object? decoded;
    try {
      decoded = jsonDecode(_b.audioTracksJson(playerId));
    } on FormatException {
      return const <VideoAudioTrack>[];
    }
    if (decoded is! List) {
      return const <VideoAudioTrack>[];
    }
    return decoded.whereType<Map<String, dynamic>>().map((Map<String, dynamic> t) {
      final String language = (t['language'] as String?) ?? '';
      return VideoAudioTrack(
        id: t['id'] as String? ?? '',
        label: t['label'] as String?,
        language: language.isEmpty ? null : language,
        isSelected: t['isSelected'] as bool? ?? false,
      );
    }).toList();
  }

  @override
  Future<void> selectAudioTrack(int playerId, String trackId) async {
    _b.selectAudioTrack(playerId, trackId);
  }
}
