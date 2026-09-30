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
}
