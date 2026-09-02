/// watchOS implementation of `games_services`.
///
/// The interface's default is `MethodChannelGamesServices`, which cannot work
/// here: watchOS has no method channels. This registers itself in its place and
/// talks to GameKit through a C ABI ([games_services_watchos_ffi.m]) resolved with
/// `DynamicLibrary.process()`.
///
/// Only the leaderboard surface is implemented. Achievements, saved games and
/// the access point are left to the interface's `UnimplementedError` defaults,
/// which is honest: `GKGameCenterViewController` and `GKAccessPoint` do not
/// exist on watchOS, so there is no way to present them.
library;

import 'dart:convert';

import 'package:games_services_platform_interface/game_services_platform_interface.dart';
import 'package:games_services_platform_interface/models.dart';

import 'src/games_services_watchos_bindings.dart';

export 'src/games_services_watchos_bindings.dart'
    show GamesServicesWatchosBindings, GcEntry;

class GamesServicesWatchos extends GamesServicesPlatform {
  /// Called by the Flutter plugin machinery on watchOS via `dartPluginClass`.
  static void registerWith() {
    GamesServicesPlatform.instance = GamesServicesWatchos();
  }

  /// Replaced by tests. Null means "use the real FFI bindings".
  static GamesServicesWatchosBindings? bindingsOverride;

  GamesServicesWatchosBindings get _native =>
      bindingsOverride ??= GamesServicesWatchosBindings();

  @override
  Future<String?> signIn() async {
    if (!_native.available) return 'Game Center unavailable';
    final ok = await _native.signIn();
    // The interface's convention is null for success, a message otherwise.
    return ok ? null : (_native.lastError ?? 'Not signed in to Game Center');
  }

  @override
  Future<String?> submitScore({required Score score}) async {
    final String? id = score.iOSLeaderboardID;
    final int? value = score.value;
    if (id == null || value == null) return 'Missing leaderboard id or value';
    if (!_native.available) return 'Game Center unavailable';
    final ok = await _native.submitScore(value, id);
    return ok ? null : (_native.lastError ?? 'Score submission failed');
  }

  /// Returns the leaderboard as a JSON string, matching the shape the
  /// method-channel implementations return so callers decode it the same way
  /// on every platform.
  ///
  /// The parameter list mirrors the interface exactly, untyped defaults and
  /// all; narrowing them to String? would not be a valid override.
  @override
  Future<String?> loadLeaderboardScores({
    dynamic iOSLeaderboardID = '',
    dynamic androidLeaderboardID = '',
    bool playerCentered = false,
    required PlayerScope scope,
    required TimeScope timeScope,
    required int maxResults,
    bool forceRefresh = false,
  }) async {
    final String id = '$iOSLeaderboardID';
    if (id.isEmpty || !_native.available) return null;
    final entries = await _native.topScores(id, count: maxResults);
    // Null propagates as null: the caller reads that as a failed load, and an
    // empty list as a leaderboard with nothing on it.
    if (entries == null) return null;
    // The shape is LeaderboardScoreData.fromJson's, exactly: it reads
    // displayScore, rawScore, timestampMillis and a nested scoreHolder
    // unchecked, so a missing key is a runtime type error rather than a null.
    //
    // playerID and teamPlayerID are null because watchOS has no stable
    // GKPlayer identifier to report -- the model already allows that, since
    // Android omits playerID for privacy. isLocal is folded into the rank
    // comparison the caller does against getPlayerScore.
    return jsonEncode(
      entries
          .map(
            (e) => <String, dynamic>{
              'rank': e.rank,
              'displayScore': '${e.score}',
              'rawScore': e.score,
              'timestampMillis': 0,
              'scoreHolder': <String, dynamic>{
                'playerID': null,
                'displayName': e.player,
                'iconImage': null,
                'teamPlayerID': null,
              },
              'token': null,
            },
          )
          .toList(),
    );
  }

  @override
  Future<int?> getPlayerScore({
    dynamic iOSLeaderboardID = '',
    dynamic androidLeaderboardID = '',
  }) async {
    final String id = '$iOSLeaderboardID';
    if (id.isEmpty || !_native.available) return null;
    // The local player's own row comes back flagged: GKPlayer has no stable
    // identifier on watchOS to match against instead.
    final entries = await _native.topScores(id, count: 100);
    if (entries == null) return null;
    for (final e in entries) {
      if (e.isLocal) return e.score;
    }
    return null;
  }
}
