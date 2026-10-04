// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The test-name step on its fixtures, in tool/words/fixtures/test_names/.

import 'dart:io';

import 'package:plugins_tool/src/forbidden_words.dart';
import 'package:plugins_tool/src/test_names.dart';
import 'package:test/test.dart';

import 'src/fixture_repo.dart';

void main() {
  final List<Fixture> fixtures = fixturesIn('words/fixtures/test_names');
  final ForbiddenWords words = ForbiddenWords.load('words/words.txt');

  group('test and group names', () {
    test('are read from every call that declares a test or a group', () {
      const String source = r'''
void main() {
  group('outer', () {
    test('one', () {});
    testWidgets('two ' 'joined', (tester) async {});
    testWithoutContext('three $value', () {});
    helper('not a test');
    expect('not a test either', isNotNull);
  });
}
''';
      expect(
        testNamesIn(source).map((TestName name) => '${name.line}:${name.text}'),
        <String>['2:outer', '3:one', '4:two joined', '5:three  '],
      );
    });

    test('are read only under test/ and example/integration_test/', () {
      expect(isTestSource('packages/a/test/a_test.dart'), isTrue);
      expect(isTestSource('packages/a/test/src/helpers.dart'), isTrue);
      expect(
        isTestSource('packages/a/example/integration_test/a_test.dart'),
        isTrue,
      );
      expect(isTestSource('packages/a/lib/a.dart'), isFalse);
      expect(isTestSource('packages/a/example/lib/main.dart'), isFalse);
      expect(isTestSource('packages/a/example/test/widget_test.dart'), isFalse);
      expect(isTestSource('tool/test/a_test.dart'), isFalse);
      expect(isTestSource('packages/a/test/data.json'), isFalse);
    });
  });

  test('there is a failing fixture of each kind', () {
    expect(
      fixtures.map((Fixture f) => f.name),
      containsAll(<String>[
        'test_dir',
        'integration_dir',
        'camel_case',
        'interpolation',
        'adjacent_strings',
      ]),
    );
    expect(fixtures.where((Fixture f) => f.expectedExitCode == 0), isNotEmpty);
  });

  for (final Fixture fixture in fixtures) {
    test('fixture ${fixture.name}', () {
      final String root = fixture.createRepository();
      addTearDown(() => Directory(root).deleteSync(recursive: true));
      final StringBuffer out = StringBuffer();
      final int code = runTestNameStep(
        root,
        words,
        WordEntries.load(fixture.pendingList),
        out,
      );
      final String output = out.toString();
      expect(code, fixture.expectedExitCode, reason: output);
      for (final String text in fixture.expectedOutput) {
        expect(output, contains(text));
      }
    });
  }
}
