// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The native AVFoundation backend is replaced with a
// fake serving scripted state snapshots, so the delegation, source mapping,
// and event derivation are verified off-device; the real AVPlayer is
// exercised by the upstream example's integration tests on the watch
// simulator.

import 'dart:async';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:audioplayers_watchos/audioplayers_watchos.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake bindings recording every call and serving a mutable state snapshot.
class _FakeBindings extends AudioplayersWatchosBindings {
  _FakeBindings() : super.forTesting();

  final List<String> calls = <String>[];
  WatchosAudioState? state;
  String errorMessage = '';
  int sourceResult = 0;

  @override
  void create(String playerId) => calls.add('create($playerId)');
  @override
  void dispose(String playerId) => calls.add('dispose($playerId)');
  @override
  int setSourceUrl(String playerId, String url, bool isLocal, String mimeType) {
    calls.add('setSourceUrl($playerId, $url, $isLocal, $mimeType)');
    return sourceResult;
  }

  @override
  int setSourceBytes(String playerId, Uint8List bytes, String extensionHint) {
    calls.add('setSourceBytes($playerId, ${bytes.length}, $extensionHint)');
    return sourceResult;
  }

  /// Result served by every control call — false simulates a disposed id.
  bool controlResult = true;

  @override
  bool resume(String playerId) {
    calls.add('resume($playerId)');
    return controlResult;
  }

  @override
  bool pause(String playerId) {
    calls.add('pause($playerId)');
    return controlResult;
  }

  @override
  bool stop(String playerId) {
    calls.add('stop($playerId)');
    return controlResult;
  }

  @override
  bool release(String playerId) {
    calls.add('release($playerId)');
    return controlResult;
  }

  @override
  bool seek(String playerId, int positionMs) {
    calls.add('seek($playerId, $positionMs)');
    return controlResult;
  }

  @override
  bool setVolume(String playerId, double volume) {
    calls.add('setVolume($playerId, $volume)');
    return controlResult;
  }

  @override
  bool setRate(String playerId, double rate) {
    calls.add('setRate($playerId, $rate)');
    return controlResult;
  }

  @override
  bool setReleaseMode(String playerId, int mode) {
    calls.add('setReleaseMode($playerId, $mode)');
    return controlResult;
  }
  @override
  WatchosAudioState? readState(String playerId) => state;
  @override
  String error(String playerId) => errorMessage;
  @override
  int setAudioContext(String category, bool mixWithOthers, bool duckOthers) {
    calls.add('setAudioContext($category, $mixWithOthers, $duckOthers)');
    return 0;
  }
}

WatchosAudioState _state({
  int status = 1,
  bool isPlaying = false,
  int preparedCount = 1,
  int seekCompleteCount = 0,
  int completeCount = 0,
  bool hasItem = true,
  int durationMs = 30000,
  int positionMs = 0,
}) {
  return WatchosAudioState(
    status: status,
    isPlaying: isPlaying,
    preparedCount: preparedCount,
    seekCompleteCount: seekCompleteCount,
    completeCount: completeCount,
    hasItem: hasItem,
    durationMs: durationMs,
    positionMs: positionMs,
  );
}

void main() {
  late _FakeBindings fake;
  late AudioplayersWatchos player;

  setUp(() {
    fake = _FakeBindings();
    AudioplayersWatchos.bindingsOverride = fake;
    AudioplayersWatchos.pollInterval = const Duration(milliseconds: 5);
    player = AudioplayersWatchos();
  });

  tearDown(() {
    AudioplayersWatchos.bindingsOverride = null;
  });

  group('registerWith', () {
    test('installs both the player and the global implementation', () {
      AudioplayersWatchos.registerWith();
      expect(AudioplayersPlatformInterface.instance, isA<AudioplayersWatchos>());
      expect(GlobalAudioplayersPlatformInterface.instance,
          isA<GlobalAudioplayersWatchos>());
    });
  });

  group('controls', () {
    test('delegate to the native player', () async {
      await player.create('p1');
      await player.resume('p1');
      await player.pause('p1');
      await player.stop('p1');
      await player.release('p1');
      await player.seek('p1', const Duration(seconds: 2));
      await player.setVolume('p1', 0.5);
      await player.setPlaybackRate('p1', 1.5);
      await player.setReleaseMode('p1', ReleaseMode.loop);
      await player.dispose('p1');
      expect(fake.calls, <String>[
        'create(p1)',
        'resume(p1)',
        'pause(p1)',
        'stop(p1)',
        'release(p1)',
        'seek(p1, 2000)',
        'setVolume(p1, 0.5)',
        'setRate(p1, 1.5)',
        'setReleaseMode(p1, ${ReleaseMode.loop.index})',
        'dispose(p1)',
      ]);
    });
  });

  group('sources', () {
    test('setSourceUrl passes url, locality, and mime type through', () async {
      await player.setSourceUrl('p1', 'https://example.com/a.mp3');
      await player.setSourceUrl('p1', '/tmp/b.mp3', isLocal: true);
      await player.setSourceUrl('p1', '/tmp/noext',
          isLocal: true, mimeType: 'audio/wav');
      expect(fake.calls, <String>[
        'setSourceUrl(p1, https://example.com/a.mp3, false, )',
        'setSourceUrl(p1, /tmp/b.mp3, true, )',
        'setSourceUrl(p1, /tmp/noext, true, audio/wav)',
      ]);
    });

    test('setSourceBytes maps the mime type to a container hint', () async {
      await player.setSourceBytes('p1', Uint8List(4), mimeType: 'audio/wav');
      expect(fake.calls, contains('setSourceBytes(p1, 4, wav)'));
    });

    test('a failed source load throws PlatformException', () {
      fake.sourceResult = -1;
      expect(
        () => player.setSourceUrl('p1', 'not a url'),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('queries', () {
    test('getDuration is null while unknown, ms when known', () async {
      fake.state = _state(durationMs: -1);
      expect(await player.getDuration('p1'), isNull);
      fake.state = _state(durationMs: 45000);
      expect(await player.getDuration('p1'), 45000);
    });

    test('getCurrentPosition is null once no source is loaded', () async {
      // Mirrors upstream: position is null when no item is loaded (never
      // set, or unloaded by release), and real once one is.
      fake.state = _state(status: 0, preparedCount: 0, hasItem: false);
      expect(await player.getCurrentPosition('p1'), isNull);
      fake.state = _state(positionMs: 1234);
      expect(await player.getCurrentPosition('p1'), 1234);
    });

    test('controls on a disposed player throw the upstream message', () async {
      fake.controlResult = false;
      await expectLater(
        () => player.stop('p1'),
        throwsA(isA<PlatformException>().having(
          (PlatformException e) => e.message,
          'message',
          'Player has not yet been created or has already been disposed.',
        )),
      );
    });
  });

  group('getEventStream', () {
    test('derives prepared + duration, seek complete, and complete events',
        () async {
      await player.create('p1');
      fake.state = _state(status: 0, preparedCount: 0, durationMs: -1);
      final List<AudioEvent> events = <AudioEvent>[];
      final StreamSubscription<AudioEvent> sub =
          player.getEventStream('p1').listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      fake.state = _state(); // prepared, 30s duration
      await Future<void>.delayed(const Duration(milliseconds: 20));
      fake.state = _state(seekCompleteCount: 1, completeCount: 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();

      expect(
        events.map((AudioEvent e) => e.eventType),
        containsAllInOrder(<AudioEventType>[
          AudioEventType.prepared,
          AudioEventType.duration,
          AudioEventType.seekComplete,
          AudioEventType.complete,
        ]),
      );
      final AudioEvent duration = events.firstWhere(
          (AudioEvent e) => e.eventType == AudioEventType.duration);
      expect(duration.duration, const Duration(seconds: 30));
    });

    test('surfaces a native failure with the upstream message contract',
        () async {
      await player.create('p1');
      fake.state = _state(status: 2, preparedCount: 0);
      fake.errorMessage = 'boom';
      await expectLater(
        player.getEventStream('p1').first,
        throwsA(isA<PlatformException>()
            .having((PlatformException e) => e.message, 'message',
                startsWith('Failed to set source.'))
            .having((PlatformException e) => '${e.details}', 'details',
                contains('boom'))),
      );
    });

    test('emitLog and emitError feed the stream directly', () async {
      await player.create('p1');
      final Future<AudioEvent> first = player.getEventStream('p1').first;
      await player.emitLog('p1', 'hello');
      final AudioEvent event = await first;
      expect(event.eventType, AudioEventType.log);
      expect(event.logMessage, 'hello');
    });
  });

  group('audio context', () {
    test('maps the iOS category and mix/duck options', () async {
      await player.setAudioContext(
        'p1',
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const <AVAudioSessionOptions>{
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
        ),
      );
      expect(fake.calls, contains('setAudioContext(playback, true, false)'));
    });
  });

  group('unsupported surfaces', () {
    test('setBalance logs instead of throwing (no AVPlayer balance)',
        () async {
      await player.create('p1');
      final Future<AudioEvent> first = player.getEventStream('p1').first;
      await player.setBalance('p1', 0.5);
      final AudioEvent event = await first;
      expect(event.eventType, AudioEventType.log);
      expect(event.logMessage, contains('not supported'));
    });
  });
}
