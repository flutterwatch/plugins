// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The example constraint lint on its fixtures, in
// tool/test/fixtures/example_constraints/.

import 'package:path/path.dart' as p;
import 'package:plugins_tool/src/example_constraints.dart';
import 'package:test/test.dart';

import 'src/fixture_repo.dart';

void main() {
  final List<Fixture> fixtures = fixturesIn(
    p.join('test', 'fixtures', 'example_constraints'),
  );

  test('a fixture example with "any" fails', () {
    expect(
      fixtures
          .singleWhere((Fixture f) => f.name == 'any_dependency')
          .expectedExitCode,
      1,
    );
  });

  for (final Fixture fixture in fixtures) {
    test('fixture ${fixture.name}', () {
      final StringBuffer out = StringBuffer();
      final int code = runExampleConstraintCheck(
        p.join(fixture.directory, 'repo'),
        out,
      );
      expect(code, fixture.expectedExitCode, reason: '$out');
      for (final String text in fixture.expectedOutput) {
        expect('$out', contains(text));
      }
    });
  }

  test('only dependencies and dev_dependencies count', () {
    expect(
      unconstrainedDependencies(
        'dependencies:\n  a: any\ndev_dependencies:\n  b:\n'
        'dependency_overrides:\n  c: any\n',
      ),
      <String>['dependencies: a', 'dev_dependencies: b'],
    );
  });

  test('a fixture example with an unpinned git dependency fails', () {
    for (final String name in <String>['git_unpinned', 'git_branch_ref']) {
      expect(
        fixtures.singleWhere((Fixture f) => f.name == name).expectedExitCode,
        1,
        reason: name,
      );
    }
  });

  test('a git dependency must name a full commit hash as its ref', () {
    const String hash = '0123456789abcdef0123456789abcdef01234567';
    expect(
      unpinnedGitDependencies(
        'dependencies:\n'
        '  url_only:\n    git: https://example.com/a.git\n'
        '  no_ref:\n    git:\n      url: https://example.com/b.git\n'
        '  branch:\n    git:\n      url: https://example.com/c.git\n'
        '      ref: main\n'
        '  short_hash:\n    git:\n      url: https://example.com/d.git\n'
        '      ref: 0123456\n'
        '  full_hash:\n    git:\n      url: https://example.com/e.git\n'
        '      ref: $hash\n'
        '  hosted: ^1.0.0\n'
        '  local:\n    path: ../\n'
        'dev_dependencies:\n'
        '  tag:\n    git:\n      url: https://example.com/f.git\n'
        '      ref: v1.0.0\n'
        'dependency_overrides:\n'
        '  overridden:\n    git: https://example.com/g.git\n',
      ),
      <String>[
        'dependencies: url_only',
        'dependencies: no_ref',
        'dependencies: branch',
        'dependencies: short_hash',
        'dev_dependencies: tag',
      ],
    );
  });
}
