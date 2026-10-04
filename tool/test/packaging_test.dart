// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// tool/check_generated_ignored.sh and tool/check_clean_tree.sh on their
// fixtures, in tool/test/fixtures/generated_ignored/ and clean_tree/.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/fixture_repo.dart';

void main() {
  for (final String check in <String>['generated_ignored', 'clean_tree']) {
    group(check, () {
      final String script = p.absolute('check_$check.sh');
      final List<Fixture> fixtures = fixturesIn(
        p.join('test', 'fixtures', check),
      );

      test('has a failing and a passing fixture', () {
        expect(
          fixtures.where((Fixture f) => f.expectedExitCode == 1),
          isNotEmpty,
        );
        expect(
          fixtures.where((Fixture f) => f.expectedExitCode == 0),
          isNotEmpty,
        );
      });

      for (final Fixture fixture in fixtures) {
        test('fixture ${fixture.name}', () {
          final String root = fixture.createRepository();
          addTearDown(() => Directory(root).deleteSync(recursive: true));
          final ProcessResult result = Process.runSync('bash', <String>[
            script,
            '--root',
            root,
          ]);
          final String output = '${result.stdout}${result.stderr}';
          expect(result.exitCode, fixture.expectedExitCode, reason: output);
          for (final String text in fixture.expectedOutput) {
            expect(output, contains(text));
          }
        });
      }
    });
  }
}
