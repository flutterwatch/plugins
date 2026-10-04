// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// tool/check_words.sh on its fixtures: a hit of each kind fails, and allowed
// or pending text passes. The fixtures are in tool/words/fixtures/check_words/.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/fixture_repo.dart';

void main() {
  final String script = p.absolute('check_words.sh');
  final List<Fixture> fixtures = fixturesIn('words/fixtures/check_words');

  test('there is a failing fixture of each kind', () {
    final Set<String> names = fixtures.map((Fixture f) => f.name).toSet();
    expect(
      names,
      containsAll(<String>[
        'prose_word',
        'camel_case',
        'plural',
        'inside_word',
        'path',
        'stale_text',
        'stale_glob',
        'pending_stale',
        'untracked',
        'cli_package_glob',
      ]),
    );
    expect(fixtures.where((Fixture f) => f.expectedExitCode == 0), isNotEmpty);
  });

  // The pending list is deleted when its last entry goes.
  test('a clean repository passes without a pending list, and says nothing of it', () {
    final Fixture clean = fixtures.singleWhere((Fixture f) => f.name == 'clean');
    final String root = clean.createRepository();
    addTearDown(() => Directory(root).deleteSync(recursive: true));
    final ProcessResult result = Process.runSync(
      'bash',
      <String>[
        script,
        '--root',
        root,
        '--allow',
        clean.allowList,
        '--pending',
        p.join(root, 'missing_pending.txt'),
      ],
      environment: <String, String>{'GITHUB_ACTIONS': ''},
    );
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(result.stderr, isEmpty);
    expect(result.stdout, isNot(contains('pending entries')));
  });

  for (final Fixture fixture in fixtures) {
    test('fixture ${fixture.name}', () {
      final String root = fixture.createRepository();
      addTearDown(() => Directory(root).deleteSync(recursive: true));
      final ProcessResult result = Process.runSync(
        'bash',
        <String>[
          script,
          '--root',
          root,
          '--allow',
          fixture.allowList,
          '--pending',
          fixture.pendingList,
        ],
        environment: <String, String>{'GITHUB_ACTIONS': ''},
      );
      final String output = '${result.stdout}${result.stderr}';
      expect(result.exitCode, fixture.expectedExitCode, reason: output);
      for (final String text in fixture.expectedOutput) {
        expect(output, contains(text));
      }
    });
  }
}
