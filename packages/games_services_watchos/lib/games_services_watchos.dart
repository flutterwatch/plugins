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

import 'package:flutter/services.dart' show PlatformException;
import 'package:games_services_platform_interface/game_services_platform_interface.dart';
import 'package:games_services_platform_interface/models.dart';

import 'src/games_services_watchos_bindings.dart';

export 'src/games_services_watchos_bindings.dart'
    show GamesServicesWatchosBindings, GcEntry;

// What games_services 5.x's iOS implementation answers (its Messages and
// PluginError), so that app code reads the same on the wrist as on the phone.
const String _authenticatedSuccessfully = 'Player authenticated successfully';
const String _alreadyAuthenticated = 'Player already authenticated';
const String _success = 'Success';
const String _failedToAuthenticate = 'failed_to_authenticate';
const String _signInUnavailable = 'sign_in_unavailable';
const String _failedToSendScore = 'failed_to_send_score';

/// The message when the plugin's native code is not in the app.
const String _unlinked =
    'Game Center is not available: the GameKit symbols are not linked into '
    'this app.';

/// watchOS implementation of [GamesServicesPlatform], over GameKit through
/// `dart:ffi`.
///
/// Implements sign-in, score submission and leaderboard reads. The other
/// members keep the interface's `UnimplementedError` default; the README's
/// "Not supported on watchOS" table lists them.
class GamesServicesWatchos extends GamesServicesPlatform {
  /// Called by the Flutter plugin machinery on watchOS via `dartPluginClass`.
  static void registerWith() {
    GamesServicesPlatform.instance = GamesServicesWatchos();
  }

  /// Replaced by tests. Null means "use the real FFI bindings".
  static GamesServicesWatchosBindings? bindingsOverride;

  GamesServicesWatchosBindings get _native =>
      bindingsOverride ??= GamesServicesWatchosBindings();

  /// Signs the local player in to Game Center, and answers as
  /// `games_services` 5.x does on iOS, so app code reads the same on the
  /// wrist as on the phone.
  ///
  /// Completes with "Player authenticated successfully" when this call signs
  /// the player in, and with "Player already authenticated" when the player
  /// already was. Otherwise it fails with a [PlatformException]: its code is
  /// `sign_in_unavailable` when GameKit has already answered this launch's
  /// sign-in without signing the player in, and `failed_to_authenticate`
  /// otherwise, with GameKit's message.
  ///
  /// A call made while another sign-in is in flight waits for that sign-in's
  /// answer. (On iOS it completes at once with "Player already
  /// authenticated", before the answer is known.)
  ///
  /// Version 0.1.0 completed with null on success and with the message on
  /// failure, as `games_services` 4.x did.
  @override
  Future<String?> signIn() async {
    final GamesServicesWatchosBindings native = _native;
    if (!native.available) {
      throw PlatformException(code: _failedToAuthenticate, message: _unlinked);
    }
    if (native.authenticated) return _alreadyAuthenticated;
    // The native side installs GameKit's authentication handler once per
    // launch. Once GameKit has answered it without signing the player in,
    // there is nothing left to ask, which iOS reports as sign_in_unavailable.
    final bool answered = native.signInFailed;
    if (await native.signIn()) return _authenticatedSuccessfully;
    if (answered) {
      throw PlatformException(
        code: _signInUnavailable,
        message: 'Game Center has already answered this launch\'s sign-in '
            'without signing the player in, and asks once per launch.',
      );
    }
    throw PlatformException(
      code: _failedToAuthenticate,
      message: native.lastError ?? 'Not signed in to Game Center',
    );
  }

  /// Submits [score] to the leaderboard its `iOSLeaderboardID` names, and
  /// answers as `games_services` 5.x does on iOS.
  ///
  /// Completes with "Success". Otherwise it fails with a [PlatformException]
  /// whose code is `failed_to_send_score`: the score has no leaderboard id or
  /// no value, the player is not signed in, or GameKit refused it, with
  /// GameKit's message.
  ///
  /// Version 0.1.0 completed with null on success and with the message on
  /// failure, as `games_services` 4.x did.
  @override
  Future<String?> submitScore({required Score score}) async {
    final String? id = score.iOSLeaderboardID;
    final int? value = score.value;
    if (id == null || id.isEmpty || value == null) {
      throw PlatformException(
        code: _failedToSendScore,
        message: 'Missing leaderboard id or value',
      );
    }
    final GamesServicesWatchosBindings native = _native;
    if (!native.available) {
      throw PlatformException(code: _failedToSendScore, message: _unlinked);
    }
    if (!native.authenticated) {
      throw PlatformException(
        code: _failedToSendScore,
        message: 'Not signed in to Game Center',
      );
    }
    if (await native.submitScore(value, id)) return _success;
    throw PlatformException(
      code: _failedToSendScore,
      message: native.lastError ?? 'Score submission failed',
    );
  }

  /// Returns the leaderboard as a JSON string, matching the shape the
  /// method-channel implementations return so callers decode it the same way
  /// on every platform.
  ///
  /// The parameter list is the interface's exactly, `String` types and
  /// defaults included.
  @override
  Future<String?> loadLeaderboardScores({
    String iOSLeaderboardID = '',
    String androidLeaderboardID = '',
    bool playerCentered = false,
    required PlayerScope scope,
    required TimeScope timeScope,
    required int maxResults,
    bool forceRefresh = false,
  }) async {
    if (iOSLeaderboardID.isEmpty || !_native.available) return null;
    final entries = await _native.topScores(
      iOSLeaderboardID,
      count: maxResults,
    );
    // Null propagates as null: the caller reads that as a failed load, and an
    // empty list as a leaderboard with nothing on it.
    if (entries == null) return null;
    // The shape is that of games_services' LeaderboardScoreData.fromJson, the
    // decoder its Leaderboards.loadLeaderboardScores runs on this string. It
    // reads rank, displayScore, rawScore, timestampMillis and scoreHolder
    // unchecked, and PlayerData.fromJson then reads scoreHolder's displayName
    // the same way, so a missing key is a runtime type error rather than a
    // null.
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
    String iOSLeaderboardID = '',
    String androidLeaderboardID = '',
  }) async {
    if (iOSLeaderboardID.isEmpty || !_native.available) return null;
    // The local player's own row comes back flagged: GKPlayer has no stable
    // identifier on watchOS to match against instead.
    final entries = await _native.topScores(iOSLeaderboardID, count: 100);
    if (entries == null) return null;
    for (final e in entries) {
      if (e.isLocal) return e.score;
    }
    return null;
  }
}
