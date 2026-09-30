// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The FFI symbol check on its fixtures, in tool/test/fixtures/symcheck/.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_tool/src/symbols.dart';
import 'package:test/test.dart';

import 'src/fixture_repo.dart';

void main() {
  final List<Fixture> fixtures = fixturesIn(
    p.join('test', 'fixtures', 'symcheck'),
  );

  test('the mismatch fixture fails', () {
    expect(
      fixtures
          .singleWhere((Fixture f) => f.name == 'mismatch')
          .expectedExitCode,
      1,
    );
  });

  for (final Fixture fixture in fixtures) {
    test('fixture ${fixture.name}', () {
      final StringBuffer out = StringBuffer();
      final int code = runSymbolCheck(
        p.join(fixture.directory, 'repo'),
        parseSymbolAllowList(
          File(p.join(fixture.directory, 'allow.yaml')).readAsStringSync(),
        ),
        out,
      );
      expect(code, fixture.expectedExitCode, reason: '$out');
      for (final String text in fixture.expectedOutput) {
        expect('$out', contains(text));
      }
    });
  }

  group('the allow-list', () {
    test('needs every field', () {
      expect(
        () => parseSymbolAllowList(
          'allow:\n  - package: a\n    symbol: a_b\n    kind: defined, not '
          'declared\n',
        ),
        throwsFormatException,
      );
    });

    test('refuses an unknown kind', () {
      expect(
        () => parseSymbolAllowList(
          'allow:\n  - package: a\n    symbol: a_b\n    kind: other\n'
          '    reason: why\n',
        ),
        throwsFormatException,
      );
    });

    test('the checked-in file parses', () {
      expect(
        parseSymbolAllowList(File('symcheck_allow.yaml').readAsStringSync()),
        isNotEmpty,
      );
    });
  });
}
