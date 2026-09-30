// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The publish dry-run report on its fixtures, in
// tool/test/fixtures/publish_dry_run/, and on a real pub run.
//
// Each fixture's pub/<package>/ holds what `dart pub publish --dry-run`
// printed and its exit code. Those of clean, warning, refused, unresolved
// and mixed were captured from Dart 3.13.4 on 2026-09-30, in a copy of the
// repository: as it is, with a modified README, without a LICENSE, and for
// video_player_watchos, whose flutter_watchos ^0.1.0 is not on pub.dev
// until the release (its last line, which names a pre-release, is left
// out). hint follows the same format with a hint in place of a warning.

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:plugins_tool/src/forbidden_words.dart';
import 'package:plugins_tool/src/publish_dry_run.dart';
import 'package:test/test.dart';

import 'src/fixture_repo.dart';

/// A runner that answers with the fixture's recorded pub output.
PubRunner recordedRunner(String fixture) {
  return (String packageDirectory) {
    final String recorded = p.join(
      fixture,
      'pub',
      p.basename(packageDirectory),
    );
    String read(String name) => File(p.join(recorded, name)).readAsStringSync();
    return (
      exitCode: int.parse(read('exit_code').trim()),
      stdout: read('stdout'),
      stderr: read('stderr'),
    );
  };
}

/// A pub.dev stand-in on the loopback interface that knows no package, as
/// for a first publish, so that a real dry-run needs no network.
Future<(int, Isolate)> startEmptyPackageServer() async {
  final ReceivePort ready = ReceivePort();
  final Isolate isolate = await Isolate.spawn(_serve, ready.sendPort);
  final int port = await ready.first as int;
  return (port, isolate);
}

Future<void> _serve(SendPort ready) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  ready.send(server.port);
  await for (final HttpRequest request in server) {
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }
}

void main() {
  final ForbiddenWords words = ForbiddenWords.load(
    p.join('words', 'words.txt'),
  );
  final List<Fixture> fixtures = fixturesIn(
    p.join('test', 'fixtures', 'publish_dry_run'),
  );

  test('a package with a warning is among the failing fixtures', () {
    expect(
      fixtures.singleWhere((Fixture f) => f.name == 'warning').expectedExitCode,
      1,
    );
  });

  for (final Fixture fixture in fixtures) {
    test('fixture ${fixture.name}', () {
      final StringBuffer out = StringBuffer();
      final int code = runPublishDryRun(
        p.join(fixture.directory, 'repo'),
        recordedRunner(fixture.directory),
        words,
        out,
      );
      expect(code, fixture.expectedExitCode, reason: '$out');
      for (final String text in fixture.expectedOutput) {
        expect('$out', contains(text));
      }
    });
  }

  group('a line with a forbidden word', () {
    final String word = words.words.first;
    final String fixture = p.join('test', 'fixtures', 'publish_dry_run');

    test('in the details is withheld, and the package fails', () {
      final PubRunner recorded = recordedRunner(p.join(fixture, 'unresolved'));
      final StringBuffer out = StringBuffer();
      final int code = runPublishDryRun(
        p.join(fixture, 'unresolved', 'repo'),
        (String directory) {
          final PubRun run = recorded(directory);
          return (
            exitCode: run.exitCode,
            stdout: run.stdout,
            stderr:
                '${run.stderr}* Consider downgrading your constraint on '
                'flutter_watchos: dart pub add flutter_watchos:^0.1.0-$word.9\n',
          );
        },
        words,
        out,
      );
      expect(code, 1);
      expect(words.wordsIn('$out'), isEmpty, reason: '$out');
      expect('$out', contains('1 line withheld'));
      expect('$out', contains('version solving failed'));
    });

    test('in the headline fails a package that has 0 warnings', () {
      final PubRunner recorded = recordedRunner(p.join(fixture, 'clean'));
      final StringBuffer out = StringBuffer();
      final int code = runPublishDryRun(
        p.join(fixture, 'clean', 'repo'),
        (String directory) {
          final PubRun run = recorded(directory);
          return (
            exitCode: run.exitCode,
            stdout: run.stdout.replaceFirst(' 0.1.0 ', ' 0.1.0-$word.1 '),
            stderr: run.stderr,
          );
        },
        words,
        out,
      );
      expect(code, 1);
      expect(words.wordsIn('$out'), isEmpty, reason: '$out');
      expect(
        '$out',
        contains('FAIL battery_plus_watchos: pub named a forbidden word'),
      );
    });
  });

  group('parseDryRun', () {
    test('reads a summary with warnings and hints', () {
      final DryRunResult result = parseDryRun((
        exitCode: 65,
        stdout: 'Package has 2 warnings and 3 hints.\n',
        stderr: '',
      ));
      expect(result.warnings, 2);
      expect(result.hints, 3);
      expect(result.passed, isFalse);
    });

    test('fails an exit code 0 without a summary', () {
      final DryRunResult result = parseDryRun((
        exitCode: 0,
        stdout: 'Validating package...\n',
        stderr: '',
      ));
      expect(result.warnings, isNull);
      expect(result.passed, isFalse);
    });
  });

  group('with the real pub', () {
    late String root;
    late int port;
    late Isolate server;

    setUp(() async {
      (port, server) = await startEmptyPackageServer();
      root = createGitRepository();
      final String package = p.join(root, 'packages', 'foo');
      Directory(p.join(package, 'lib')).createSync(recursive: true);
      File(p.join(package, 'pubspec.yaml')).writeAsStringSync(
        'name: foo\n'
        'description: A package for the publish dry-run test, with a '
        'description of the length pub asks for.\n'
        'version: 0.1.0\n'
        'repository: https://github.com/flutterwatch/plugins\n'
        'environment:\n'
        '  sdk: ^3.0.0\n',
      );
      File(
        p.join(package, 'CHANGELOG.md'),
      ).writeAsStringSync('## 0.1.0\n\n* First version.\n');
      File(p.join(package, 'README.md')).writeAsStringSync('# foo\n');
      File(
        p.join(package, 'LICENSE'),
      ).writeAsStringSync(File(p.join('..', 'LICENSE')).readAsStringSync());
      File(
        p.join(package, 'lib', 'foo.dart'),
      ).writeAsStringSync('/// One.\nint foo() => 1;\n');
      File(
        p.join(root, '.gitignore'),
      ).writeAsStringSync('.dart_tool/\npubspec.lock\n');
      commitAll(root, 'foo');
    });

    tearDown(() {
      server.kill();
      Directory(root).deleteSync(recursive: true);
    });

    PubRunner runner() => dartPubRunner(
      environment: <String, String>{
        'PUB_HOSTED_URL': 'http://127.0.0.1:$port',
        'PUB_CACHE': p.join(root, '.pub-cache'),
      },
    );

    test('a clean package passes', () {
      final StringBuffer out = StringBuffer();
      expect(runPublishDryRun(root, runner(), words, out), 0, reason: '$out');
      expect('$out', contains('ok   foo 0.1.0'));
    });

    test('a modified checked-in file is a warning', () {
      File(
        p.join(root, 'packages', 'foo', 'README.md'),
      ).writeAsStringSync('# foo, changed\n');
      final StringBuffer out = StringBuffer();
      expect(runPublishDryRun(root, runner(), words, out), 1, reason: '$out');
      expect('$out', contains('FAIL foo 0.1.0'));
      expect('$out', contains('modified in git'));
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}
