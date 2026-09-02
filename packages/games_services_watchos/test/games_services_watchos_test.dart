// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:games_services_platform_interface/game_services_platform_interface.dart';
import 'package:games_services/games_services.dart' show LeaderboardScoreData;
import 'package:games_services_platform_interface/models.dart';
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
    return true;
  }

  @override
  Future<List<GcEntry>?> topScores(
    String leaderboardId, {
    int count = 10,
    Duration timeout = const Duration(seconds: 20),
  }) async {
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

void main() {
  tearDown(() => GamesServicesWatchos.bindingsOverride = null);

  test('registerWith installs the watchOS implementation', () {
    GamesServicesWatchos.registerWith();
    expect(GamesServicesPlatform.instance, isA<GamesServicesWatchos>());
  });

  test('signIn reports null on success, a message on failure', () async {
    GamesServicesWatchos.bindingsOverride = _FakeBindings();
    expect(await GamesServicesWatchos().signIn(), isNull);

    GamesServicesWatchos.bindingsOverride = _FakeBindings(signedIn: false);
    expect(await GamesServicesWatchos().signIn(), isNotNull);
  });

  test('submitScore passes the iOS leaderboard id and value through', () async {
    final fake = _FakeBindings();
    GamesServicesWatchos.bindingsOverride = fake;
    final err = await GamesServicesWatchos().submitScore(
      score: Score(iOSLeaderboardID: 'board.id', value: 42),
    );
    expect(err, isNull);
    expect(fake.submitted, 1);
    expect(fake.lastSubmittedScore, 42);
  });

  test('submitScore refuses a score with no leaderboard or value', () async {
    GamesServicesWatchos.bindingsOverride = _FakeBindings();
    expect(await GamesServicesWatchos().submitScore(score: Score()), isNotNull);
  });

  test('loadLeaderboardScores emits the shape the upstream model reads', () async {
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

    // The upstream model reads these keys unchecked, so a missing one is a
    // runtime type error rather than a null -- which is exactly how a wrong
    // shape reaches a user instead of a test.
    final rows = (jsonDecode(raw!) as List)
        .map((e) => LeaderboardScoreData.fromJson(e as Map<String, dynamic>))
        .toList();
    expect(rows, hasLength(2));
    expect(rows.first.rank, 1);
    expect(rows.first.rawScore, 900);
    expect(rows.first.displayScore, '900');
    expect(rows.first.scoreHolder.displayName, 'Gardener');
    // No stable player identifier exists on watchOS.
    expect(rows.first.scoreHolder.playerID, isNull);
  });

  test('a failed read is null, an empty leaderboard is an empty list', () async {
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

  test('getPlayerScore returns the local row, or null when absent', () async {
    GamesServicesWatchos.bindingsOverride = _FakeBindings(
      entries: const <GcEntry>[_first, _mine],
    );
    expect(
      await GamesServicesWatchos().getPlayerScore(iOSLeaderboardID: 'board.id'),
      250,
    );

    GamesServicesWatchos.bindingsOverride = _FakeBindings(
      entries: const <GcEntry>[_first],
    );
    expect(
      await GamesServicesWatchos().getPlayerScore(iOSLeaderboardID: 'board.id'),
      isNull,
    );
  });

  test('unimplemented surfaces keep the interface defaults', () async {
    GamesServicesWatchos.bindingsOverride = _FakeBindings();
    final plugin = GamesServicesWatchos();
    expect(() => plugin.showLeaderboards(), throwsUnimplementedError);
    expect(() => plugin.showAchievements(), throwsUnimplementedError);
    expect(
      () => plugin.unlock(achievement: Achievement(androidID: 'a', iOSID: 'b')),
      throwsUnimplementedError,
    );
  });
}
