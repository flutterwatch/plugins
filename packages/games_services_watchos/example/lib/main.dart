// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_watchos/flutter_watchos.dart';
import 'package:games_services/games_services.dart';

/// Replace with a leaderboard id from your own App Store Connect record; a
/// simulator has no Game Center account, so the interesting states here are
/// the failures, and they are the point of the example.
const String kLeaderboardId = 'your.leaderboard.id';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Scaffold(body: _Body()));
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final List<String> _log = <String>[];

  /// Read once, so a rebuild does not subscribe again. It gives the current
  /// sign-in state at once, and a new one when a call changes it.
  final Stream<PlayerData?> _player = GameAuth.player;

  void _say(String line) => setState(() => _log.insert(0, line));

  // As on iOS with games_services 5.x, signIn and submitScore complete with
  // a message on success and throw a PlatformException on failure.
  Future<void> _signIn() async {
    try {
      _say(await GameAuth.signIn() ?? 'signed in');
    } on PlatformException catch (e) {
      _say('sign-in failed: ${e.message}');
    }
  }

  Future<void> _submit() async {
    try {
      await GamesServices.submitScore(
        score: Score(iOSLeaderboardID: kLeaderboardId, value: 10),
      );
      _say('submitted 10');
    } on PlatformException catch (e) {
      _say('submit failed: ${e.message}');
    }
  }

  Future<void> _load() async {
    final List<LeaderboardScoreData>? rows =
        await Leaderboards.loadLeaderboardScores(
      iOSLeaderboardID: kLeaderboardId,
      scope: PlayerScope.global,
      timeScope: TimeScope.allTime,
      maxResults: 5,
    );
    // Null and empty mean different things, and the example says which.
    if (rows == null) {
      _say('load failed');
    } else if (rows.isEmpty) {
      _say('no scores');
    } else {
      _say(rows.map((r) => '${r.rank}. ${r.displayScore}').join('  '));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      // No SafeArea, so the list fills the screen the way a native watchOS
      // list does: rows scroll under the clock and down to the bottom edge.
      // The insets go into the list's padding instead. The default safe area
      // leaves the clock out of MediaQuery's padding, so the top comes from
      // WatchStatusBar.heightOf, the clock's band, in either safe area; the
      // other sides take MediaQuery's insets, so the rows stay clear of the
      // rounded corners and the last one scrolls clear of the bottom edge.
      padding: MediaQuery.paddingOf(context)
              .copyWith(top: WatchStatusBar.heightOf(context)) +
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      children: <Widget>[
        StreamBuilder<PlayerData?>(
          stream: _player,
          builder: (BuildContext context, AsyncSnapshot<PlayerData?> player) {
            final String? name = player.data?.displayName;
            return Text(
              name == null ? 'signed out' : 'signed in as $name',
              style: const TextStyle(fontSize: 12),
            );
          },
        ),
        TextButton(onPressed: _signIn, child: const Text('Sign in')),
        TextButton(onPressed: _submit, child: const Text('Submit 10')),
        TextButton(onPressed: _load, child: const Text('Load scores')),
        for (final String line in _log)
          Text(line, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
