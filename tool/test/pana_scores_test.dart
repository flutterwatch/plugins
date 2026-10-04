// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The pana comparison on its fixtures, in tool/test/fixtures/pana_scores/.
// The reports are `pana --json` output of pana 0.23.19 with Flutter 3.47.5,
// run on 2026-09-30 on battery_plus_watchos (140), url_launcher_watchos
// (130), games_services_watchos (120) and flutter_watch_link (150), trimmed
// to the parts the check reads. ios_full, ios_without_platform_points and
// watchos_with_platform_points change one section's points of those.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_tool/src/forbidden_words.dart';
import 'package:plugins_tool/src/pana_scores.dart';
import 'package:test/test.dart';

import 'src/fixture_repo.dart';

void main() {
  final ForbiddenWords words = ForbiddenWords.load(
    p.join('words', 'words.txt'),
  );
  final String fixtureRoot = p.join('test', 'fixtures', 'pana_scores');
  final List<Fixture> fixtures = fixturesIn(fixtureRoot);

  test('a package that loses points is among the failing fixtures', () {
    expect(
      fixtures
          .singleWhere((Fixture f) => f.name == 'lost_convention')
          .expectedExitCode,
      1,
    );
  });

  for (final Fixture fixture in fixtures) {
    test('fixture ${fixture.name}', () {
      final StringBuffer out = StringBuffer();
      final int code = runPanaScores(
        p.join(fixture.directory, 'repo'),
        p.join(fixture.directory, 'reports'),
        words,
        out,
      );
      expect(code, fixture.expectedExitCode, reason: '$out');
      for (final String text in fixture.expectedOutput) {
        expect('$out', contains(text));
      }
    });
  }

  test('scoredPlatforms keeps the platforms pana knows', () {
    expect(
      scoredPlatforms(
        'flutter:\n  plugin:\n    platforms:\n'
        '      ios:\n        ffiPlugin: true\n'
        '      watchos:\n        ffiPlugin: true\n',
      ),
      <String>{'ios'},
    );
    expect(
      scoredPlatforms(
        'flutter:\n  plugin:\n    platforms:\n'
        '      watchos:\n        ffiPlugin: true\n',
      ),
      isEmpty,
    );
    expect(scoredPlatforms('name: not_a_plugin\n'), isEmpty);
  });

  test('a report line with a forbidden word is withheld and fails', () {
    final String fixture = p.join(fixtureRoot, 'lost_convention');
    final Map<String, Object?> report =
        jsonDecode(
              File(
                p.join(fixture, 'reports', 'url_launcher_watchos.json'),
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final List<Object?> sections =
        (report['report']! as Map<String, Object?>)['sections']!
            as List<Object?>;
    final Map<String, Object?> convention =
        sections.first! as Map<String, Object?>;
    convention['summary'] =
        '### [x] 0/10 points: a ${words.words.first} check\n';
    final Directory reports = Directory.systemTemp.createTempSync(
      'pana_reports_',
    );
    addTearDown(() => reports.deleteSync(recursive: true));
    File(
      p.join(reports.path, 'url_launcher_watchos.json'),
    ).writeAsStringSync(jsonEncode(report));

    final StringBuffer out = StringBuffer();
    final int code = runPanaScores(
      p.join(fixture, 'repo'),
      reports.path,
      words,
      out,
    );
    expect(code, 1);
    expect(words.wordsIn('$out'), isEmpty, reason: '$out');
    expect('$out', contains('1 line withheld'));
  });

  test('a report that does not parse fails', () {
    final Directory reports = Directory.systemTemp.createTempSync(
      'pana_reports_',
    );
    addTearDown(() => reports.deleteSync(recursive: true));
    File(
      p.join(reports.path, 'battery_plus_watchos.json'),
    ).writeAsStringSync('{"packageName": "battery_plus_watchos"}');
    final StringBuffer out = StringBuffer();
    final int code = runPanaScores(
      p.join(fixtureRoot, 'watchos_only', 'repo'),
      reports.path,
      words,
      out,
    );
    expect(code, 1);
    expect('$out', contains('The report does not parse'));
  });
}
