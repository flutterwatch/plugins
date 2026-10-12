/// watchOS implementation of `games_services`.
///
/// The interface's default is `MethodChannelGamesServices`, which cannot work
/// here: watchOS has no method channels. This registers itself in its place and
/// talks to GameKit through a C ABI ([games_services_watchos_ffi.m]) resolved with
/// `DynamicLibrary.process()`.
///
/// Only sign-in, the player stream and the leaderboard surface are
/// implemented. Achievements, saved games and the access point are left to
/// the interface's `UnimplementedError` defaults, which is honest:
/// `GKGameCenterViewController`, `GKAccessPoint` and `GKSavedGame` do not
/// exist on watchOS, so there is no way to present or call them.
library;

import 'dart:async';
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
/// Implements sign-in, the player stream, score submission and leaderboard
/// reads. The other members keep the interface's `UnimplementedError`
/// default; the README's "Not supported on watchOS" table lists them.
class GamesServicesWatchos extends GamesServicesPlatform {
  /// Called by the Flutter plugin machinery on watchOS via `dartPluginClass`.
  static void registerWith() {
    GamesServicesPlatform.instance = GamesServicesWatchos();
  }

  /// Replaced by tests. Null means "use the real FFI bindings".
  static GamesServicesWatchosBindings? bindingsOverride;

  GamesServicesWatchosBindings get _native =>
      bindingsOverride ??= GamesServicesWatchosBindings();

  /// One entry per [player] subscriber: it re-reads the state and sends an
  /// event when it changed.
  final Set<void Function()> _playerListeners = <void Function()>{};

  /// The signed-in local player, or null while nobody is signed in, seeded
  /// with the live state for every subscriber.
  ///
  /// `games_services` 5.x reads it for `GameAuth.isSignedIn`, `GameAuth.player`
  /// and the getters of its `Player` class. The [PlayerData] carries GameKit's
  /// alias as its `displayName`. Its `playerID` and `teamPlayerID` are null,
  /// because watchOS has no stable player identifier, and so are `iconImage`
  /// and the three restriction flags, which the native side does not report.
  ///
  /// Each subscriber's first event is the live state. After that, each of
  /// this plugin's calls (sign-in, submission and the leaderboard reads)
  /// re-reads the state when it finishes, and a subscriber gets an event when
  /// the state changed. The native side reports nothing by itself, so a change
  /// GameKit makes between calls, such as a sign-in that lapses when the watch
  /// loses its phone, reaches a subscriber at the next call. A new subscriber
  /// sees it at once.
  ///
  /// Every read returns the same stream, as the method-channel implementation
  /// does, so a `StreamBuilder` that reads `GameAuth.player` in `build` keeps
  /// its subscription across rebuilds.
  @override
  Stream<PlayerData?> get player => _player;

  /// [Stream.multi] rather than a broadcast controller: a broadcast `onListen`
  /// fires only for the first subscriber, so a later one would never be told
  /// the current state. Each listen gets its own controller here.
  late final Stream<PlayerData?> _player = Stream<PlayerData?>.multi(
    _listenToPlayer,
    isBroadcast: true,
  );

  void _listenToPlayer(MultiStreamController<PlayerData?> out) {
    bool seeded = false;
    PlayerData? last;
    void update() {
      final PlayerData? now = _localPlayer();
      if (seeded && _samePlayer(last, now)) return;
      seeded = true;
      last = now;
      // add, not addSync: a subscriber runs in a later microtask, never
      // inside the plugin call that noticed the change.
      out.add(now);
    }

    _playerListeners.add(update);
    out.onCancel = () {
      _playerListeners.remove(update);
    };
    update();
  }

  /// The local player as GameKit reports it now, or null when nobody is
  /// signed in or the GameKit symbols are not linked.
  PlayerData? _localPlayer() {
    final GamesServicesWatchosBindings native = _native;
    if (!native.authenticated) return null;
    return PlayerData(playerID: null, displayName: native.playerAlias ?? '');
  }

  /// Whether [a] and [b] describe the same state. Only the alias can differ
  /// between two players here; every other field is null on watchOS.
  static bool _samePlayer(PlayerData? a, PlayerData? b) =>
      a == null ? b == null : b != null && a.displayName == b.displayName;

  /// Tells every [player] subscriber to re-read the state, from a copy of the
  /// set, since a subscriber may cancel while it is told.
  void _playerMayHaveChanged() {
    for (final void Function() update in _playerListeners.toList()) {
      update();
    }
  }

  /// Signs the local player in to Game Center, and answers as
  /// `games_services` 5.x does on iOS, so app code reads the same on the
  /// wrist as on the phone.
  ///
  /// Completes with "Player authenticated successfully" when this call signs
  /// the player in, and with "Player already authenticated" when the player
  /// already was. Otherwise it fails with a [PlatformException]: its code is
  /// `sign_in_unavailable` when GameKit has already answered this launch's
  /// sign-in and the player is not signed in, since the plugin asks once per
  /// launch, and `failed_to_authenticate` otherwise, with GameKit's message.
  ///
  /// A call made while another sign-in is in flight waits for that sign-in's
  /// answer. (On iOS it completes at once with "Player already
  /// authenticated", before the answer is known.)
  ///
  /// Version 0.1.0 completed with null on success and with the message on
  /// failure, as `games_services` 4.x did.
  @override
  Future<String?> signIn() async {
    try {
      return await _signIn();
    } finally {
      _playerMayHaveChanged();
    }
  }

  Future<String?> _signIn() async {
    final GamesServicesWatchosBindings native = _native;
    if (!native.available) {
      throw PlatformException(code: _failedToAuthenticate, message: _unlinked);
    }
    if (native.authenticated) return _alreadyAuthenticated;
    // The native side installs GameKit's authentication handler once per
    // launch. Once GameKit has answered it and the player is not signed in,
    // whether that answer failed or the sign-in lapsed since, there is
    // nothing left to ask, which iOS reports as sign_in_unavailable.
    final bool answered = native.signInFailed;
    if (await native.signIn()) return _authenticatedSuccessfully;
    if (answered) {
      throw PlatformException(
        code: _signInUnavailable,
        message: 'Game Center has already answered this launch\'s sign-in, '
            'and the player is not signed in; the plugin asks once per '
            'launch.',
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
    try {
      return await _submitScore(score);
    } finally {
      _playerMayHaveChanged();
    }
  }

  Future<String?> _submitScore(Score score) async {
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
    final List<GcEntry>? entries;
    try {
      entries = await _native.topScores(iOSLeaderboardID, count: maxResults);
    } finally {
      // A read signs in again when the sign-in has lapsed.
      _playerMayHaveChanged();
    }
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
    final List<GcEntry>? entries;
    try {
      entries = await _native.topScores(iOSLeaderboardID, count: 100);
    } finally {
      _playerMayHaveChanged();
    }
    if (entries == null) return null;
    for (final e in entries) {
      if (e.isLocal) return e.score;
    }
    return null;
  }
}
