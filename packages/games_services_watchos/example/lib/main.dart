// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
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

  void _say(String line) => setState(() => _log.insert(0, line));

  Future<void> _signIn() async {
    final String? error = await GameAuth.signIn();
    _say(error == null ? 'signed in' : 'sign-in failed: $error');
  }

  Future<void> _submit() async {
    final String? error = await GamesServices.submitScore(
      score: Score(iOSLeaderboardID: kLeaderboardId, value: 10),
    );
    _say(error == null ? 'submitted 10' : 'submit failed: $error');
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
      padding: const EdgeInsets.all(8),
      children: <Widget>[
        TextButton(onPressed: _signIn, child: const Text('Sign in')),
        TextButton(onPressed: _submit, child: const Text('Submit 10')),
        TextButton(onPressed: _load, child: const Text('Load scores')),
        for (final String line in _log)
          Text(line, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
