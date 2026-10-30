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

    // A plugin's `defines` turn its macros on per app, so its sources are
    // compiled with no -D (an older CLI), with the marker and every macro,
    // and with the marker alone. A plugin without them is compiled once.
    test('plans three passes for a plugin with defines, one for the rest', () {
      final Fixture fixture = named('plan_defines');
      final ProcessResult result = run(fixture, <String>['--list']);
      expectFixture(fixture, result);
      final List<String> lines = '${result.stdout}'.split('\n');
      expect(
        lines.where((String l) => l.contains('d_watchos_ffi.m')),
        hasLength(6),
        reason: 'three passes, for a watch and the Simulator',
      );
      expect(lines.where((String l) => l.contains('e_watchos_ffi.m')), <String>[
        'plan   clang   watchos arm64-apple-watchos26.0 '
            'packages/e_watchos/watchos/Classes/e_watchos_ffi.m',
        'plan   clang   watchsimulator arm64-apple-watchos26.0-simulator '
            'packages/e_watchos/watchos/Classes/e_watchos_ffi.m',
      ]);
    });

    test('a declaration the CLI refuses fails before anything is planned', () {
      final Fixture fixture = named('defines_invalid');
      final ProcessResult result = run(fixture, <String>['--list']);
      expectFixture(fixture, result);
      expect('${result.stdout}', isNot(contains('plan ')));
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

    test('guards right on both sides pass in every pass', () {
      final Fixture fixture = named('compile_defines');
      expectFixture(fixture, run(fixture, <String>[]));
    });

    // The guarded function is called from outside its guard: that compiles
    // with no -D and with every macro, and fails for an app without the key.
    test(
      'a guard wrong only without its macro fails in the marker-alone pass',
      () {
        final Fixture fixture = named('compile_defines_guard');
        final ProcessResult result = run(fixture, <String>[]);
        expectFixture(fixture, result);
        final List<String> lines = '${result.stdout}'.split('\n');
        final List<String> failed = lines
            .where((String l) => l.startsWith('FAILED'))
            .toList();
        expect(failed, hasLength(2), reason: 'a watch and the Simulator');
        expect(failed, everyElement(endsWith('[marker alone]')));
        expect(
          lines.where((String l) => l.startsWith('ok ')),
          hasLength(4),
          reason: 'no -D, and the marker with every macro, for each target',
        );
      },
    );
  }, skip: Platform.isMacOS ? false : 'needs Xcode');
}
