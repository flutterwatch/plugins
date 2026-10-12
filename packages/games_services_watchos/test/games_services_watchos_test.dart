// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host tests over fake bindings: no FFI, no GameKit. Every public member of
// games_services_platform_interface 5.3.0 has a case here. The members this
// package implements are checked against games_services 5.3.0 itself, its
// models and the decoders its app-facing classes run on what this package
// returns; every other member must keep the interface's default.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:games_services/games_services.dart';
import 'package:games_services_platform_interface/game_services_platform_interface.dart';
import 'package:games_services_watchos/games_services_watchos.dart';

/// Fake bindings — no FFI, no GameKit, scripted answers.
class _FakeBindings extends GamesServicesWatchosBindings {
  _FakeBindings({
    this.signedIn = true,
    this.entries = const <GcEntry>[],
    this.readFails = false,
  }) : super.forTesting();

  bool signedIn;
  List<GcEntry> entries;

  /// Distinct from an empty [entries]: this is the read failing outright.
  bool readFails;

  int submitted = 0;
  int? lastSubmittedScore;
  String? lastLeaderboardId;
  int? lastCount;

  @override
  bool get available => true;

  @override
  bool get authenticated => signedIn;

  @override
  Future<bool> signIn({Duration timeout = const Duration(seconds: 20)}) async =>
      signedIn;

  @override
  Future<bool> submitScore(
    int score,
    String leaderboardId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!signedIn) return false;
    submitted++;
    lastSubmittedScore = score;
    lastLeaderboardId = leaderboardId;
    return true;
  }

  @override
  Future<List<GcEntry>?> topScores(
    String leaderboardId, {
    int count = 10,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    lastLeaderboardId = leaderboardId;
    lastCount = count;
    if (!signedIn || readFails) return null;
    return entries.take(count).toList();
  }
}

const GcEntry _first = GcEntry(
  rank: 1,
  score: 900,
  player: 'Gardener',
  isLocal: false,
);
const GcEntry _mine = GcEntry(rank: 2, score: 250, player: 'Me', isLocal: true);

/// Expects [call] to return a future that fails with an
/// [UnimplementedError], which is what the interface's `async` defaults do;
/// calling the member must not throw by itself.
Future<void> _expectFailsUnimplemented(
  Future<Object?> Function() call,
) async {
  Future<Object?>? result;
  expect(() => result = call(), returnsNormally);
  await expectLater(result, throwsUnimplementedError);
}

/// Expects [call] itself to throw an [UnimplementedError], which is what the
/// interface's non-`async` defaults do.
void _expectThrowsUnimplemented(Object? Function() call) {
  Object? error;
  try {
    call();
  } catch (e) {
    error = e;
  }
  expect(error, isUnimplementedError);
}

void main() {
  tearDown(() => GamesServicesWatchos.bindingsOverride = null);

  test('registerWith installs the watchOS implementation', () {
    GamesServicesWatchos.registerWith();
    expect(GamesServicesPlatform.instance, isA<GamesServicesWatchos>());
  });

  group('signIn', () {
    test('reports null on success, a message on failure', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings();
      expect(await GamesServicesWatchos().signIn(), isNull);

      GamesServicesWatchos.bindingsOverride = _FakeBindings(signedIn: false);
      expect(await GamesServicesWatchos().signIn(), isNotNull);
    });
  });

  group('submitScore', () {
    test('passes the iOS leaderboard id and value through', () async {
      final fake = _FakeBindings();
      GamesServicesWatchos.bindingsOverride = fake;
      final err = await GamesServicesWatchos().submitScore(
        score: Score(iOSLeaderboardID: 'board.id', value: 42),
      );
      expect(err, isNull);
      expect(fake.submitted, 1);
      expect(fake.lastSubmittedScore, 42);
      expect(fake.lastLeaderboardId, 'board.id');
    });

    test('refuses a score with no leaderboard or value', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings();
      expect(
        await GamesServicesWatchos().submitScore(score: Score()),
        isNotNull,
      );
    });
  });

  group('loadLeaderboardScores', () {
    test('returns rows that games_services 5.3.0 decodes', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(
        entries: const <GcEntry>[_first, _mine],
      );
      final raw = await GamesServicesWatchos().loadLeaderboardScores(
        iOSLeaderboardID: 'board.id',
        scope: PlayerScope.global,
        timeScope: TimeScope.allTime,
        maxResults: 10,
      );
      expect(raw, isNotNull);

      // LeaderboardScoreData.fromJson reads rank, displayScore, rawScore,
      // timestampMillis and scoreHolder unchecked, and PlayerData.fromJson
      // reads the scoreHolder's displayName the same way, so a missing or
      // mistyped key is a runtime type error here rather than a null.
      final rows = (jsonDecode(raw!) as List)
          .map((e) => LeaderboardScoreData.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(rows, hasLength(2));
      expect(rows.first.rank, 1);
      expect(rows.first.rawScore, 900);
      expect(rows.first.displayScore, '900');
      expect(rows.first.timestampMillis, 0);
      expect(rows.first.token, isNull);
      expect(rows.first.scoreHolder.displayName, 'Gardener');
      // No stable player identifier exists on watchOS.
      expect(rows.first.scoreHolder.playerID, isNull);
      expect(rows.first.scoreHolder.teamPlayerID, isNull);
      expect(rows.first.scoreHolder.iconImage, isNull);
      expect(rows.last.rank, 2);
      expect(rows.last.scoreHolder.displayName, 'Me');
    });

    test('decodes through Leaderboards.loadLeaderboardScores', () async {
      final fake = _FakeBindings(entries: const <GcEntry>[_first, _mine]);
      GamesServicesWatchos.bindingsOverride = fake;
      GamesServicesWatchos.registerWith();
      final List<LeaderboardScoreData>? rows =
          await Leaderboards.loadLeaderboardScores(
        iOSLeaderboardID: 'board.id',
        scope: PlayerScope.global,
        timeScope: TimeScope.allTime,
        maxResults: 1,
      );
      expect(fake.lastLeaderboardId, 'board.id');
      expect(fake.lastCount, 1);
      expect(rows, isNotNull);
      expect(rows!.single.scoreHolder.displayName, 'Gardener');
    });

    test('a failed read is null, an empty leaderboard is an empty list',
        () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(readFails: true);
      expect(
        await GamesServicesWatchos().loadLeaderboardScores(
          iOSLeaderboardID: 'board.id',
          scope: PlayerScope.global,
          timeScope: TimeScope.allTime,
          maxResults: 10,
        ),
        isNull,
        reason: 'a failed read must not look like an empty leaderboard',
      );

      GamesServicesWatchos.bindingsOverride = _FakeBindings();
      final raw = await GamesServicesWatchos().loadLeaderboardScores(
        iOSLeaderboardID: 'board.id',
        scope: PlayerScope.global,
        timeScope: TimeScope.allTime,
        maxResults: 10,
      );
      expect(jsonDecode(raw!), isEmpty);
    });

    test('is null without an iOS leaderboard id', () async {
      final fake = _FakeBindings(entries: const <GcEntry>[_first]);
      GamesServicesWatchos.bindingsOverride = fake;
      expect(
        await GamesServicesWatchos().loadLeaderboardScores(
          androidLeaderboardID: 'android.board',
          scope: PlayerScope.global,
          timeScope: TimeScope.allTime,
          maxResults: 10,
        ),
        isNull,
      );
      expect(fake.lastLeaderboardId, isNull, reason: 'nothing was read');
    });
  });

  group('getPlayerScore', () {
    test('returns the local row through Player.getPlayerScore', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(
        entries: const <GcEntry>[_first, _mine],
      );
      GamesServicesWatchos.registerWith();
      expect(await Player.getPlayerScore(iOSLeaderboardID: 'board.id'), 250);
    });

    test('is null when the local player has no row', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(
        entries: const <GcEntry>[_first],
      );
      expect(
        await GamesServicesWatchos().getPlayerScore(
          iOSLeaderboardID: 'board.id',
        ),
        isNull,
      );
    });
  });

  // The rest of the 5.3.0 interface, one case per member, each called with
  // the parameters 5.3.0 gives it.
  group('keeps the interface default', () {
    late GamesServicesWatchos plugin;
    final Achievement achievement = Achievement(
      androidID: 'android.id',
      iOSID: 'ios.id',
      steps: 5,
    );

    setUp(() {
      GamesServicesWatchos.bindingsOverride = _FakeBindings();
      plugin = GamesServicesWatchos();
    });

    test('player', () {
      _expectThrowsUnimplemented(() => plugin.player);
    });

    test('increment', () async {
      await _expectFailsUnimplemented(
        () => plugin.increment(achievement: achievement),
      );
    });

    test('setSteps', () async {
      await _expectFailsUnimplemented(
        () => plugin.setSteps(achievement: achievement),
      );
    });

    test('unlock', () async {
      await _expectFailsUnimplemented(
        () => plugin.unlock(achievement: achievement),
      );
    });

    test('showAchievements', () async {
      await _expectFailsUnimplemented(() => plugin.showAchievements());
    });

    test('showLeaderboards', () async {
      await _expectFailsUnimplemented(
        () => plugin.showLeaderboards(
          iOSLeaderboardID: 'board.id',
          timeScope: TimeScope.week,
          playerScope: PlayerScope.friendsOnly,
        ),
      );
    });

    test('loadAchievements', () async {
      await _expectFailsUnimplemented(
        () => plugin.loadAchievements(forceRefresh: true, ignoreImages: true),
      );
    });

    test('resetAchievements', () async {
      await _expectFailsUnimplemented(() => plugin.resetAchievements());
    });

    test('getPlayerScoreObject', () async {
      await _expectFailsUnimplemented(
        () => plugin.getPlayerScoreObject(
          iOSLeaderboardID: 'board.id',
          scope: PlayerScope.global,
          timeScope: TimeScope.allTime,
        ),
      );
    });

    test('loadPreviousOccurrence', () async {
      await _expectFailsUnimplemented(
        () => plugin.loadPreviousOccurrence(
          iOSLeaderboardID: 'board.id',
          timeScope: TimeScope.allTime,
        ),
      );
    });

    test('getAuthCode', () {
      _expectThrowsUnimplemented(
        () => plugin.getAuthCode('client.id', forceRefreshToken: true),
      );
    });

    test('showAccessPoint', () async {
      await _expectFailsUnimplemented(
        () => plugin.showAccessPoint(AccessPointLocation.topLeading),
      );
    });

    test('hideAccessPoint', () async {
      await _expectFailsUnimplemented(() => plugin.hideAccessPoint());
    });

    test('getPlayerHiResImage', () async {
      await _expectFailsUnimplemented(() => plugin.getPlayerHiResImage());
    });

    test('saveGame', () async {
      await _expectFailsUnimplemented(
        () => plugin.saveGame(
          data: '{}',
          name: 'slot1',
          coverImage: Uint8List(0),
          description: 'level 1',
          playedTime: const Duration(minutes: 1),
        ),
      );
    });

    test('loadGame', () async {
      await _expectFailsUnimplemented(() => plugin.loadGame(name: 'slot1'));
    });

    test('deleteGame', () async {
      await _expectFailsUnimplemented(() => plugin.deleteGame(name: 'slot1'));
    });

    test('showSavedGames', () async {
      await _expectFailsUnimplemented(
        () => plugin.showSavedGames(title: 'Saved games', maxResults: 3),
      );
    });

    test('getSavedGames', () async {
      await _expectFailsUnimplemented(
        () => plugin.getSavedGames(forceRefresh: true, ignoreImages: true),
      );
    });

    test('fetchIdentityVerificationSignature', () async {
      await _expectFailsUnimplemented(
        () => plugin.fetchIdentityVerificationSignature(),
      );
    });
  });
}
