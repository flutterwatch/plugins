// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Runs on the watch simulator against the real FFI implementation. Upstream
// `games_services` ships no integration test to port, so this is ours, and it
// is written for what a simulator can actually prove.
//
// A simulator has no Game Center account, so no call here can succeed. That is
// deliberate: what this asserts is that the plugin is *linked and registered*,
// and that every unauthenticated path degrades instead of throwing. The first
// of those is not reachable from a host test -- symbols that were silently
// dead-stripped still pass `flutter test` and fail only on a device.

import 'package:flutter_test/flutter_test.dart';
import 'package:games_services/games_services.dart';
import 'package:games_services_platform_interface/game_services_platform_interface.dart';
import 'package:games_services_watchos/games_services_watchos.dart';
import 'package:integration_test/integration_test.dart';

const String _leaderboard = 'test.leaderboard';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the watchOS implementation is the registered platform', (
    WidgetTester _,
  ) async {
    expect(GamesServicesPlatform.instance, isA<GamesServicesWatchos>());
  });

  testWidgets('the native symbols are linked into the binary', (
    WidgetTester _,
  ) async {
    // The real check this file exists for. `available` is true only when every
    // symbol resolved through DynamicLibrary.process(); a missing `used`
    // attribute or a pubspec ffiSymbols entry left behind shows up here and
    // nowhere else.
    expect(
      GamesServicesWatchosBindings().available,
      isTrue,
      reason: 'FFI symbols missing -- check ffiSymbols and the used attribute',
    );
  });

  testWidgets('sign-in reports failure rather than throwing', (
    WidgetTester _,
  ) async {
    // No Game Center account on a simulator, so this must fail politely.
    expect(await GameAuth.signIn(), isNotNull);
  });

  testWidgets('submitting while unauthenticated fails without throwing', (
    WidgetTester _,
  ) async {
    expect(
      await GamesServices.submitScore(
        score: Score(iOSLeaderboardID: _leaderboard, value: 1),
      ),
      isNotNull,
    );
  });

  testWidgets('a failed read is null, never an empty leaderboard', (
    WidgetTester _,
  ) async {
    // The distinction this plugin exists to keep: collapsing them made a
    // broken leaderboard read as an empty one all the way up to the UI.
    expect(
      await Leaderboards.loadLeaderboardScores(
        iOSLeaderboardID: _leaderboard,
        scope: PlayerScope.global,
        timeScope: TimeScope.allTime,
        maxResults: 5,
      ),
      isNull,
    );
  });

  testWidgets('unsupported surfaces keep the interface defaults', (
    WidgetTester _,
  ) async {
    // GKGameCenterViewController does not exist on watchOS; the interface's
    // throwing default is the honest answer, not a silent no-op.
    await expectLater(
      Leaderboards.showLeaderboards(iOSLeaderboardID: _leaderboard),
      throwsUnimplementedError,
    );
  });
}
