// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// tool/check_native_sources.sh on its fixtures, in
// tool/test/fixtures/check_native_sources/. `--list` runs anywhere, so the
// plan fixtures run on every machine. The compile fixtures need Xcode, so
// they run on macOS only: the CI job that compiles the native sources runs
// this file there.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/fixture_repo.dart';

void main() {
  final String script = p.absolute('check_native_sources.sh');
  final List<Fixture> fixtures = fixturesIn(
    p.join('test', 'fixtures', 'check_native_sources'),
  );

  /// Runs the script on [fixture]'s repository, with [arguments].
  ProcessResult run(Fixture fixture, List<String> arguments) {
    final String root = fixture.createRepository();
    addTearDown(() => Directory(root).deleteSync(recursive: true));
    return Process.runSync('bash', <String>[
      script,
      '--root',
      root,
      ...arguments,
    ]);
  }

  /// Checks [result] against [fixture]'s `expect` file.
  void expectFixture(Fixture fixture, ProcessResult result) {
    final String output = '${result.stdout}${result.stderr}';
    expect(result.exitCode, fixture.expectedExitCode, reason: output);
    for (final String line in fixture.expectedOutput) {
      expect(output, contains(line));
    }
  }

  Fixture named(String name) =>
      fixtures.singleWhere((Fixture f) => f.name == name);

  group('--list', () {
    test('plans what the CLI compiles, and nothing else', () {
      final Fixture fixture = named('plan');
      final ProcessResult result = run(fixture, <String>['--list']);
      expectFixture(fixture, result);
      final String output = '${result.stdout}';
      expect(output, isNot(contains('scratch.m')), reason: 'untracked');
      expect(
        output,
        isNot(contains('Flutter/Generated.swift')),
        reason: 'CLI build output',
      );
      expect(
        output,
        isNot(contains('example/watchos')),
        reason: "the example's app",
      );
      expect(
        output,
        isNot(contains('b_watchos_ffi.m')),
        reason: 'a SwiftPM-dependency package is skipped',
      );
    });

    test('a repository with no native source fails', () {
      final Fixture fixture = named('no_sources');
      expectFixture(fixture, run(fixture, <String>['--list']));
    });
  });

  group('compiles', () {
    test('a clean source passes, and a deprecation is counted', () {
      final Fixture fixture = named('compile_clean');
      expectFixture(fixture, run(fixture, <String>[]));
    });

    test('an undeclared symbol fails', () {
      final Fixture fixture = named('compile_undeclared');
      expectFixture(fixture, run(fixture, <String>[]));
    });

    test('a warning that is not a deprecation fails', () {
      final Fixture fixture = named('compile_warning');
      expectFixture(fixture, run(fixture, <String>[]));
    });
  }, skip: Platform.isMacOS ? false : 'needs Xcode');
}
