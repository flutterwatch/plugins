// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The native AVFoundation backend is replaced with a
// fake serving scripted state snapshots, so the source mapping, event
// derivation, and control plumbing are verified off-device; the real
// AVPlayer + platform view are exercised by the upstream example's
// integration test on the watch simulator.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_player_watchos/video_player_watchos.dart';

/// Fake bindings recording every call and serving a mutable state snapshot.
class _FakeBindings extends VideoPlayerWatchosBindings {
  _FakeBindings() : super.forTesting();

  final List<String> calls = <String>[];
  WatchosVideoState? state;
  String errorMessage = '';
  int positionMs = 0;
  int nextPlayerId = 7;

  @override
  int create(String uri, int sourceType) {
    calls.add('create($uri, $sourceType)');
    return nextPlayerId;
  }

  @override
  void dispose(int playerId) => calls.add('dispose($playerId)');
  @override
  void play(int playerId) => calls.add('play($playerId)');
  @override
  void pause(int playerId) => calls.add('pause($playerId)');
  @override
  void setVolume(int playerId, double volume) =>
      calls.add('setVolume($playerId, $volume)');
  @override
  void setLooping(int playerId, bool looping) =>
      calls.add('setLooping($playerId, $looping)');
  @override
  void setSpeed(int playerId, double speed) =>
      calls.add('setSpeed($playerId, $speed)');
  @override
  void seek(int playerId, int positionMs) =>
      calls.add('seek($playerId, $positionMs)');
  @override
  int position(int playerId) => positionMs;
  @override
  WatchosVideoState? readState(int playerId) => state;
  @override
  String error(int playerId) => errorMessage;
  @override
  void setMixWithOthers(bool mix) => calls.add('setMixWithOthers($mix)');
  @override
  void registerViews() => calls.add('registerViews()');

  String audioTracksJsonValue = '[]';
  @override
  String audioTracksJson(int playerId) {
    calls.add('audioTracksJson($playerId)');
    return audioTracksJsonValue;
  }

  @override
  bool selectAudioTrack(int playerId, String trackId) {
    calls.add('selectAudioTrack($playerId, $trackId)');
    return true;
  }
}

WatchosVideoState _state({
  int status = 1,
  bool isPlaying = false,
  int bufferingStartCount = 0,
  int bufferingEndCount = 0,
  int completedCount = 0,
  int durationMs = 60000,
  int bufferedMs = 0,
  double width = 320,
  double height = 240,
}) {
  return WatchosVideoState(
    status: status,
    isPlaying: isPlaying,
    bufferingStartCount: bufferingStartCount,
    bufferingEndCount: bufferingEndCount,
    completedCount: completedCount,
    durationMs: durationMs,
    bufferedMs: bufferedMs,
    width: width,
    height: height,
  );
}

void main() {
  late _FakeBindings fake;
  late VideoPlayerWatchos player;

  setUp(() {
    fake = _FakeBindings();
    VideoPlayerWatchos.bindingsOverride = fake;
    VideoPlayerWatchos.pollInterval = const Duration(milliseconds: 5);
    player = VideoPlayerWatchos();
  });

  tearDown(() {
    VideoPlayerWatchos.bindingsOverride = null;
  });

  group('registerWith', () {
    test('installs the instance and registers the native view factory', () {
      VideoPlayerWatchos.registerWith();
      expect(VideoPlayerPlatform.instance, isA<VideoPlayerWatchos>());
      expect(fake.calls, contains('registerViews()'));
    });
  });

  group('create', () {
    test('passes a network uri through as source type 0', () async {
      final int? id = await player.create(DataSource(
        sourceType: DataSourceType.network,
        uri: 'https://example.com/v.m3u8',
      ));
      expect(id, 7);
      expect(fake.calls, contains('create(https://example.com/v.m3u8, 0)'));
    });

    test('converts a file:// uri to a path with source type 1', () async {
      await player.create(DataSource(
        sourceType: DataSourceType.file,
        uri: 'file:///tmp/movie.mp4',
      ));
      expect(fake.calls, contains('create(/tmp/movie.mp4, 1)'));
    });

    test('builds the flutter asset key with source type 2', () async {
      await player.create(DataSource(
        sourceType: DataSourceType.asset,
        asset: 'assets/movie.mp4',
        package: 'some_pkg',
      ));
      expect(
        fake.calls,
        contains('create(packages/some_pkg/assets/movie.mp4, 2)'),
      );
    });

    test('rejects content uris (Android-only)', () {
      expect(
        () => player.create(DataSource(
          sourceType: DataSourceType.contentUri,
          uri: 'content://media/1',
        )),
        throwsUnsupportedError,
      );
    });

    test('throws PlatformException when the native create fails', () {
      fake.nextPlayerId = -1;
      expect(
        () => player.create(DataSource(
          sourceType: DataSourceType.network,
          uri: 'not a url',
        )),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('controls', () {
    test('delegate to the native player', () async {
      await player.play(7);
      await player.pause(7);
      await player.setVolume(7, 0.5);
      await player.setLooping(7, true);
      await player.setPlaybackSpeed(7, 1.5);
      await player.seekTo(7, const Duration(seconds: 3));
      await player.setMixWithOthers(true);
      await player.dispose(7);
      expect(fake.calls, <String>[
        'play(7)',
        'pause(7)',
        'setVolume(7, 0.5)',
        'setLooping(7, true)',
        'setSpeed(7, 1.5)',
        'seek(7, 3000)',
        'setMixWithOthers(true)',
        'dispose(7)',
      ]);
    });

    test('getPosition reads the native position', () async {
      fake.positionMs = 1234;
      expect(await player.getPosition(7), const Duration(milliseconds: 1234));
    });
  });

  group('videoEventsFor', () {
    test('emits initialized once the player becomes ready', () async {
      fake.state = _state(durationMs: 90000, width: 640, height: 360);
      final VideoEvent event = await player.videoEventsFor(7).first;
      expect(event.eventType, VideoEventType.initialized);
      expect(event.duration, const Duration(milliseconds: 90000));
      expect(event.size, const Size(640, 360));
    });

    test('derives completed, buffering, and play-state events by diffing',
        () async {
      fake.state = _state();
      final List<VideoEvent> events = <VideoEvent>[];
      final StreamSubscription<VideoEvent> sub =
          player.videoEventsFor(7).listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      fake.state = _state(isPlaying: true, bufferedMs: 5000);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      fake.state =
          _state(isPlaying: false, bufferedMs: 5000, completedCount: 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();

      expect(
        events.map((VideoEvent e) => e.eventType),
        containsAllInOrder(<VideoEventType>[
          VideoEventType.initialized,
          VideoEventType.isPlayingStateUpdate,
          VideoEventType.completed,
        ]),
      );
      final VideoEvent bufferingUpdate = events.firstWhere(
          (VideoEvent e) => e.eventType == VideoEventType.bufferingUpdate);
      expect(
        bufferingUpdate.buffered,
        <DurationRange>[
          DurationRange(Duration.zero, const Duration(milliseconds: 5000)),
        ],
      );
    });

    test('replays buffering edges missed between polls from the counters',
        () async {
      fake.state = _state();
      final List<VideoEventType> events = <VideoEventType>[];
      final StreamSubscription<VideoEvent> sub = player
          .videoEventsFor(7)
          .listen((VideoEvent e) => events.add(e.eventType));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // A full stall (start+end) happened entirely between two polls.
      fake.state = _state(bufferingStartCount: 1, bufferingEndCount: 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      expect(
        events,
        containsAllInOrder(<VideoEventType>[
          VideoEventType.bufferingStart,
          VideoEventType.bufferingEnd,
        ]),
      );
    });

    test('surfaces a native failure as a PlatformException error', () async {
      fake.state = _state(status: 2);
      fake.errorMessage = 'boom';
      await expectLater(
        player.videoEventsFor(7).first,
        throwsA(isA<PlatformException>()
            .having((PlatformException e) => e.message, 'message', 'boom')),
      );
    });
  });

  group('buildView', () {
    test('embeds the platform view in the underlay layer', () {
      final Widget view = player.buildViewWithOptions(
        const VideoViewOptions(playerId: 7),
      );
      expect(view, isA<WatchPlatformView>());
      final WatchPlatformView platformView = view as WatchPlatformView;
      expect(platformView.viewType, VideoPlayerWatchos.viewType);
      expect(platformView.creationParams, '7');
      expect(platformView.layer, WatchPlatformViewLayer.belowFlutter);
    });
  });

  group('audio tracks', () {
    test('support is advertised as available', () {
      expect(player.isAudioTrackSupportAvailable(), isTrue);
    });

    test('getAudioTracks is empty for a video with no selection group',
        () async {
      fake.audioTracksJsonValue = '[]';
      expect(await player.getAudioTracks(7), isEmpty);
    });

    test('getAudioTracks maps the native JSON into VideoAudioTracks',
        () async {
      fake.audioTracksJsonValue =
          '[{"id":"0","label":"English","language":"en","isSelected":true},'
          '{"id":"1","label":"Español","language":"","isSelected":false}]';
      final List<VideoAudioTrack> tracks = await player.getAudioTracks(7);
      expect(tracks, hasLength(2));
      expect(tracks[0].id, '0');
      expect(tracks[0].label, 'English');
      expect(tracks[0].language, 'en');
      expect(tracks[0].isSelected, isTrue);
      // An empty language string becomes null (not reported by the platform).
      expect(tracks[1].language, isNull);
      expect(tracks[1].isSelected, isFalse);
    });

    test('malformed native JSON degrades to an empty list', () async {
      fake.audioTracksJsonValue = 'not json';
      expect(await player.getAudioTracks(7), isEmpty);
    });

    test('selectAudioTrack forwards the id to the native side', () async {
      await player.selectAudioTrack(7, '1');
      expect(fake.calls, contains('selectAudioTrack(7, 1)'));
    });
  });
}
