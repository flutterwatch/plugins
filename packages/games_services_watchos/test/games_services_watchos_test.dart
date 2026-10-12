// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host tests over fake bindings: no FFI, no GameKit. Every public member of
// games_services_platform_interface 5.3.0 has a case here. The members this
// package implements are checked against games_services 5.3.0 itself, its
// models and the decoders its app-facing classes run on what this package
// returns; every other member must keep the interface's default.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:games_services/games_services.dart';
import 'package:games_services_platform_interface/game_services_platform_interface.dart';
import 'package:games_services_watchos/games_services_watchos.dart';

/// Fake bindings — no FFI, no GameKit, scripted answers. The sign-in follows
/// the native side's states: a launch asks GameKit once, so a sign-in that
/// failed or lapsed is not asked again, and a read asks only when nothing has
/// asked yet.
class _FakeBindings extends GamesServicesWatchosBindings {
  _FakeBindings({
    bool linked = true,
    bool signedIn = true,
    this.signInSucceeds = true,
    this.signInError,
    this.submitError,
    this.alias = 'Me',
    this.entries = const <GcEntry>[],
    this.readFails = false,
  })  : state = !linked
            ? GcAuthState.unavailable
            : (signedIn ? GcAuthState.signedIn : GcAuthState.idle),
        super.forTesting();

  /// The native sign-in state. A test sets it directly for what GameKit does
  /// between the plugin's calls.
  GcAuthState state;

  /// When set, each read of [authState] first moves [state] to the next entry
  /// here, and the last one stays: a state that changes between two reads.
  List<GcAuthState>? reads;

  /// Whether a sign-in that GameKit has not answered yet ends signed in.
  bool signInSucceeds;

  /// Whether GameKit leaves a sign-in unanswered until the wait runs out.
  bool signInTimesOut = false;

  Duration? lastSignInTimeout;

  /// GameKit's message when the sign-in fails.
  String? signInError;

  /// GameKit's message when a submission fails; null means it succeeds.
  String? submitError;

  /// The signed-in player's alias.
  String alias;

  List<GcEntry> entries;

  /// Distinct from an empty [entries]: this is the read failing outright.
  bool readFails;

  String? error;
  int signIns = 0;
  int aliasReads = 0;
  int submitted = 0;
  int? lastSubmittedScore;
  String? lastLeaderboardId;
  int? lastCount;

  @override
  GcAuthState get authState {
    final List<GcAuthState>? next = reads;
    if (next != null && next.isNotEmpty) {
      state = next.length > 1 ? next.removeAt(0) : next.single;
    }
    return state;
  }

  @override
  String? get lastError => error;

  @override
  String? get playerAlias {
    aliasReads++;
    return state == GcAuthState.signedIn ? alias : null;
  }

  @override
  Future<bool> signIn({Duration timeout = const Duration(seconds: 20)}) async {
    signIns++;
    lastSignInTimeout = timeout;
    switch (state) {
      case GcAuthState.unavailable:
      case GcAuthState.failed:
        // GameKit has answered this launch, so there is nothing to ask.
        return false;
      case GcAuthState.signedIn:
        return true;
      case GcAuthState.idle:
      case GcAuthState.pending:
        if (signInTimesOut) {
          state = GcAuthState.pending;
          return false;
        }
        if (signInSucceeds) {
          state = GcAuthState.signedIn;
          return true;
        }
        error = signInError;
        state = GcAuthState.failed;
        return false;
    }
  }

  @override
  Future<bool> submitScore(
    int score,
    String leaderboardId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (state != GcAuthState.signedIn) return false;
    lastLeaderboardId = leaderboardId;
    if (submitError != null) {
      error = submitError;
      return false;
    }
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
    lastLeaderboardId = leaderboardId;
    lastCount = count;
    // As the real bindings do, a read that finds the player signed out asks
    // GameKit to sign in first.
    if (state != GcAuthState.signedIn && !await signIn(timeout: timeout)) {
      return null;
    }
    if (readFails) return null;
    return entries.take(count).toList();
  }
}

/// The plugin's message when its native code is not in the app.
const String _notLinked =
    'Game Center is not available: the GameKit symbols are not linked into '
    'this app.';

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

/// A [PlatformException] with [code], and with [message] when it is given.
Matcher _platformException(String code, {String? message}) {
  Matcher matcher = isA<PlatformException>().having(
    (PlatformException e) => e.code,
    'code',
    code,
  );
  if (message != null) {
    matcher = allOf(
      matcher,
      isA<PlatformException>().having(
        (PlatformException e) => e.message,
        'message',
        message,
      ),
    );
  }
  return matcher;
}

void main() {
  tearDown(() => GamesServicesWatchos.bindingsOverride = null);

  test('registerWith installs the watchOS implementation', () {
    GamesServicesWatchos.registerWith();
    expect(GamesServicesPlatform.instance, isA<GamesServicesWatchos>());
  });

  // games_services 5.x answers on iOS with a message on success and a
  // PlatformException on failure; these hold the watch to the same answers,
  // through 5.3.0's own GameAuth and Leaderboards where an app would call.
  group('signIn', () {
    test('answers "Player authenticated successfully" when it signs in',
        () async {
      final fake = _FakeBindings(signedIn: false);
      GamesServicesWatchos.bindingsOverride = fake;
      GamesServicesWatchos.registerWith();
      expect(await GameAuth.signIn(), 'Player authenticated successfully');
      expect(fake.signIns, 1);
    });

    test('answers "Player already authenticated" when already signed in',
        () async {
      final fake = _FakeBindings();
      GamesServicesWatchos.bindingsOverride = fake;
      GamesServicesWatchos.registerWith();
      expect(await GameAuth.signIn(), 'Player already authenticated');
      expect(fake.signIns, 0, reason: 'nothing to ask GameKit');
    });

    test('fails with failed_to_authenticate and GameKit\'s message', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(
        signedIn: false,
        signInSucceeds: false,
        signInError: 'The user canceled.',
      );
      GamesServicesWatchos.registerWith();
      await expectLater(
        GameAuth.signIn(),
        throwsA(
          _platformException(
            'failed_to_authenticate',
            message: 'The user canceled.',
          ),
        ),
      );
    });

    test('fails with sign_in_unavailable once GameKit has answered', () async {
      final fake = _FakeBindings(signedIn: false, signInSucceeds: false);
      GamesServicesWatchos.bindingsOverride = fake;
      final plugin = GamesServicesWatchos();
      await expectLater(
        plugin.signIn(),
        throwsA(_platformException('failed_to_authenticate')),
      );
      await expectLater(
        plugin.signIn(),
        throwsA(_platformException('sign_in_unavailable')),
      );
    });

    test('fails with failed_to_authenticate when GameKit is not linked',
        () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(linked: false);
      await expectLater(
        GamesServicesWatchos().signIn(),
        throwsA(
          _platformException('failed_to_authenticate', message: _notLinked),
        ),
      );
    });

    test('fails with sign_in_unavailable after the sign-in lapsed', () async {
      final fake = _FakeBindings();
      GamesServicesWatchos.bindingsOverride = fake;
      final plugin = GamesServicesWatchos();
      expect(await plugin.signIn(), 'Player already authenticated');
      // The watch loses its phone and GameKit drops the sign-in. The handler
      // has answered this launch, so there is nothing left to ask, as after
      // a failed sign-in.
      fake.state = GcAuthState.failed;
      await expectLater(
        plugin.signIn(),
        throwsA(_platformException('sign_in_unavailable')),
      );
    });

    test('fails with failed_to_authenticate after 20 s without an answer',
        () async {
      final fake = _FakeBindings(signedIn: false)..signInTimesOut = true;
      GamesServicesWatchos.bindingsOverride = fake;
      await expectLater(
        GamesServicesWatchos().signIn(),
        throwsA(
          _platformException(
            'failed_to_authenticate',
            message: 'Game Center did not answer the sign-in within 20 '
                'seconds; it may still sign the player in.',
          ),
        ),
      );
      expect(fake.lastSignInTimeout, const Duration(seconds: 20));
    });

    test('puts the message in details too, as iOS does', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(
        signedIn: false,
        signInSucceeds: false,
        signInError: 'The user canceled.',
      );
      await expectLater(
        GamesServicesWatchos().signIn(),
        throwsA(
          isA<PlatformException>().having(
            (PlatformException e) => e.details,
            'details',
            'The user canceled.',
          ),
        ),
      );
    });

    test('decides from one read of the sign-in state', () async {
      // A sign-in already in flight fails between two reads of the state.
      // A call that read the state twice would see "in flight", then
      // "answered", and report sign_in_unavailable for the attempt it joined;
      // read once, the call reports that attempt's failure.
      final fake = _FakeBindings(signedIn: false, signInSucceeds: false)
        ..reads = <GcAuthState>[GcAuthState.pending, GcAuthState.failed];
      GamesServicesWatchos.bindingsOverride = fake;
      await expectLater(
        GamesServicesWatchos().signIn(),
        throwsA(_platformException('failed_to_authenticate')),
      );
    });
  });

  group('submitScore', () {
    test('answers "Success" and passes the iOS leaderboard id and value',
        () async {
      final fake = _FakeBindings();
      GamesServicesWatchos.bindingsOverride = fake;
      GamesServicesWatchos.registerWith();
      expect(
        await Leaderboards.submitScore(
          score: Score(iOSLeaderboardID: 'board.id', value: 42),
        ),
        'Success',
      );
      expect(fake.submitted, 1);
      expect(fake.lastSubmittedScore, 42);
      expect(fake.lastLeaderboardId, 'board.id');
    });

    test('fails with failed_to_send_score and GameKit\'s message', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(
        submitError: 'The requested leaderboard does not exist.',
      );
      await expectLater(
        GamesServicesWatchos().submitScore(
          score: Score(iOSLeaderboardID: 'board.id', value: 42),
        ),
        throwsA(
          _platformException(
            'failed_to_send_score',
            message: 'The requested leaderboard does not exist.',
          ),
        ),
      );
    });

    test('puts the message in details too, as iOS does', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(
        submitError: 'The requested leaderboard does not exist.',
      );
      await expectLater(
        GamesServicesWatchos().submitScore(
          score: Score(iOSLeaderboardID: 'board.id', value: 42),
        ),
        throwsA(
          isA<PlatformException>().having(
            (PlatformException e) => e.details,
            'details',
            'The requested leaderboard does not exist.',
          ),
        ),
      );
    });

    test('fails with failed_to_send_score while signed out', () async {
      final fake = _FakeBindings(signedIn: false);
      GamesServicesWatchos.bindingsOverride = fake;
      await expectLater(
        GamesServicesWatchos().submitScore(
          score: Score(iOSLeaderboardID: 'board.id', value: 42),
        ),
        throwsA(
          _platformException(
            'failed_to_send_score',
            message: 'Not signed in to Game Center',
          ),
        ),
      );
      expect(fake.submitted, 0);
    });

    test('fails with failed_to_send_score without a leaderboard or value',
        () async {
      final fake = _FakeBindings();
      GamesServicesWatchos.bindingsOverride = fake;
      for (final Score score in <Score>[
        Score(),
        Score(iOSLeaderboardID: 'board.id'),
        Score(iOSLeaderboardID: '', value: 42),
        Score(androidLeaderboardID: 'android.board', value: 42),
      ]) {
        await expectLater(
          GamesServicesWatchos().submitScore(score: score),
          throwsA(_platformException('failed_to_send_score')),
        );
      }
      expect(fake.submitted, 0);
    });

    test('fails with failed_to_send_score when GameKit is not linked',
        () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(linked: false);
      await expectLater(
        GamesServicesWatchos().submitScore(
          score: Score(iOSLeaderboardID: 'board.id', value: 42),
        ),
        throwsA(
            _platformException('failed_to_send_score', message: _notLinked)),
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

  // games_services 5.x reads the player stream for GameAuth.isSignedIn and
  // for its Player getters, so these go through those classes.
  group('player', () {
    test('every read is the same stream', () {
      GamesServicesWatchos.bindingsOverride = _FakeBindings();
      GamesServicesWatchos.registerWith();
      // A StreamBuilder compares its stream with the last build's, so a new
      // stream on each read would resubscribe it on every rebuild.
      expect(GameAuth.player, same(GameAuth.player));
    });

    test('a new subscriber gets null while signed out', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(signedIn: false);
      GamesServicesWatchos.registerWith();
      expect(await GameAuth.player.first, isNull);
      expect(await GameAuth.isSignedIn, isFalse);
      await expectLater(
        Player.getPlayerName(),
        throwsA(_platformException('not_authenticated')),
      );
    });

    test('a new subscriber gets the local player while signed in', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(alias: 'Gardener');
      GamesServicesWatchos.registerWith();
      final PlayerData? player = await GameAuth.player.first;
      expect(player, isNotNull);
      expect(player!.displayName, 'Gardener');
      // No stable player identifier exists on watchOS, and the native side
      // reports no photo and no restriction flags.
      expect(player.playerID, isNull);
      expect(player.teamPlayerID, isNull);
      expect(player.iconImage, isNull);
      expect(player.isUnderage, isNull);
      expect(player.isMultiplayerGamingRestricted, isNull);
      expect(player.isPersonalizedCommunicationRestricted, isNull);

      expect(await GameAuth.isSignedIn, isTrue);
      expect(await Player.getPlayerName(), 'Gardener');
      expect(await Player.getPlayerID(), isNull);
      expect(await Player.isUnderage, isNull);
    });

    test('isSignedIn lets go of its subscription', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(signedIn: false);
      GamesServicesWatchos.registerWith();
      expect(await GameAuth.isSignedIn, isFalse);
      // isSignedIn completes from the first event and cancels. This change
      // must not reach that subscription, which would complete its future a
      // second time; a new call reads the new state.
      await GameAuth.signIn();
      await pumpEventQueue();
      expect(await GameAuth.isSignedIn, isTrue);
    });

    test('a sign-in reaches every subscriber, once each', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(signedIn: false);
      GamesServicesWatchos.registerWith();
      final List<String?> first = <String?>[];
      final List<String?> second = <String?>[];
      final StreamSubscription<PlayerData?> a = GameAuth.player.listen(
        (PlayerData? p) => first.add(p?.displayName),
      );
      final StreamSubscription<PlayerData?> b = GameAuth.player.listen(
        (PlayerData? p) => second.add(p?.displayName),
      );
      addTearDown(a.cancel);
      addTearDown(b.cancel);
      await pumpEventQueue();
      expect(first, <String?>[null]);
      expect(second, <String?>[null]);

      await GameAuth.signIn();
      await pumpEventQueue();
      expect(first, <String?>[null, 'Me']);
      expect(second, <String?>[null, 'Me']);

      // Signed in already: nothing changed, so nothing is sent.
      await GameAuth.signIn();
      await pumpEventQueue();
      expect(first, <String?>[null, 'Me']);
      expect(second, <String?>[null, 'Me']);
    });

    test('a later subscriber starts from the current state', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(signedIn: false);
      GamesServicesWatchos.registerWith();
      final StreamSubscription<PlayerData?> early = GameAuth.player.listen(
        (_) {},
      );
      addTearDown(early.cancel);
      await GameAuth.signIn();
      expect((await GameAuth.player.first)?.displayName, 'Me');
    });

    test('a failed sign-in leaves the subscribers on null', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(
        signedIn: false,
        signInSucceeds: false,
      );
      GamesServicesWatchos.registerWith();
      final List<PlayerData?> events = <PlayerData?>[];
      final StreamSubscription<PlayerData?> sub = GameAuth.player.listen(
        events.add,
      );
      addTearDown(sub.cancel);
      await expectLater(
        GameAuth.signIn(),
        throwsA(isA<PlatformException>()),
      );
      await pumpEventQueue();
      expect(events, <PlayerData?>[null]);
    });

    test('a lapsed sign-in reaches subscribers at the next call', () async {
      final fake = _FakeBindings();
      GamesServicesWatchos.bindingsOverride = fake;
      GamesServicesWatchos.registerWith();
      final List<String?> events = <String?>[];
      final StreamSubscription<PlayerData?> sub = GameAuth.player.listen(
        (PlayerData? p) => events.add(p?.displayName),
      );
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(events, <String?>['Me']);

      // GameKit drops the sign-in, say when the watch loses its phone. The
      // native side reports nothing until the plugin is called again.
      fake.state = GcAuthState.failed;
      await expectLater(
        GamesServices.submitScore(
          score: Score(iOSLeaderboardID: 'board.id', value: 1),
        ),
        throwsA(isA<PlatformException>()),
      );
      await pumpEventQueue();
      expect(events, <String?>['Me', null]);
    });

    test('a failed read reaches subscribers', () async {
      final fake = _FakeBindings(entries: const <GcEntry>[_first]);
      GamesServicesWatchos.bindingsOverride = fake;
      GamesServicesWatchos.registerWith();
      final List<String?> events = <String?>[];
      final StreamSubscription<PlayerData?> sub = GameAuth.player.listen(
        (PlayerData? p) => events.add(p?.displayName),
      );
      addTearDown(sub.cancel);
      await pumpEventQueue();

      // The sign-in lapses; the read cannot sign in again and fails.
      fake.state = GcAuthState.failed;
      expect(
        await Leaderboards.loadLeaderboardScores(
          iOSLeaderboardID: 'board.id',
          scope: PlayerScope.global,
          timeScope: TimeScope.allTime,
          maxResults: 10,
        ),
        isNull,
      );
      await pumpEventQueue();
      expect(events, <String?>['Me', null]);
    });

    test('a failed score read reaches subscribers', () async {
      final fake = _FakeBindings(entries: const <GcEntry>[_mine]);
      GamesServicesWatchos.bindingsOverride = fake;
      GamesServicesWatchos.registerWith();
      final List<String?> events = <String?>[];
      final StreamSubscription<PlayerData?> sub = GameAuth.player.listen(
        (PlayerData? p) => events.add(p?.displayName),
      );
      addTearDown(sub.cancel);
      await pumpEventQueue();

      fake.state = GcAuthState.failed;
      expect(await Player.getPlayerScore(iOSLeaderboardID: 'board.id'), isNull);
      await pumpEventQueue();
      expect(events, <String?>['Me', null]);
    });

    test('a new subscriber reads the state live, with no call between',
        () async {
      final fake = _FakeBindings();
      GamesServicesWatchos.bindingsOverride = fake;
      GamesServicesWatchos.registerWith();
      final StreamSubscription<PlayerData?> early = GameAuth.player.listen(
        (_) {},
      );
      addTearDown(early.cancel);
      await pumpEventQueue();

      // GameKit drops the sign-in, and no call of the plugin follows.
      fake.state = GcAuthState.failed;
      expect(await GameAuth.player.first, isNull);
      expect(await GameAuth.isSignedIn, isFalse);
    });

    test('a cancelled subscriber is not read for again', () async {
      final fake = _FakeBindings();
      GamesServicesWatchos.bindingsOverride = fake;
      GamesServicesWatchos.registerWith();
      final StreamSubscription<PlayerData?> sub = GameAuth.player.listen(
        (_) {},
      );
      await pumpEventQueue();
      await sub.cancel();
      fake.aliasReads = 0;
      await GamesServices.submitScore(
        score: Score(iOSLeaderboardID: 'board.id', value: 1),
      );
      expect(fake.aliasReads, 0, reason: 'nobody is subscribed any more');
    });

    test('a cancelled subscriber gets nothing more', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(signedIn: false);
      GamesServicesWatchos.registerWith();
      final List<PlayerData?> events = <PlayerData?>[];
      final StreamSubscription<PlayerData?> sub = GameAuth.player.listen(
        events.add,
      );
      await pumpEventQueue();
      await sub.cancel();
      await GameAuth.signIn();
      await pumpEventQueue();
      expect(events, <PlayerData?>[null]);
    });

    test('says signed out when GameKit is not linked', () async {
      GamesServicesWatchos.bindingsOverride = _FakeBindings(linked: false);
      GamesServicesWatchos.registerWith();
      expect(await GameAuth.player.first, isNull);
      expect(await GameAuth.isSignedIn, isFalse);
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
