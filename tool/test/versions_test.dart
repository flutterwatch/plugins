// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The version check on its fixtures, in tool/test/fixtures/versions/. Each
// fixture's repo/ is committed as the published state, and its untracked/
// and deleted files make the current state.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_tool/src/published_files.dart';
import 'package:plugins_tool/src/versions.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'src/fixture_repo.dart';

void main() {
  final List<Fixture> fixtures = fixturesIn(
    p.join('test', 'fixtures', 'versions'),
  );

  test('a changed file with an unchanged version is among the fixtures', () {
    final Fixture fixture = fixtures.singleWhere(
      (Fixture f) => f.name == 'changed_same_version',
    );
    expect(fixture.expectedExitCode, 1);
  });

  for (final Fixture fixture in fixtures) {
    test('fixture ${fixture.name}', () {
      final String root = createGitRepository();
      addTearDown(() => Directory(root).deleteSync(recursive: true));
      copyTree(p.join(fixture.directory, 'repo'), root);
      final String base = commitAll(root, 'published');
      final Directory untracked = Directory(
        p.join(fixture.directory, 'untracked'),
      );
      if (untracked.existsSync()) {
        copyTree(untracked.path, root);
      }
      final File deleted = File(p.join(fixture.directory, 'deleted'));
      if (deleted.existsSync()) {
        for (final String path in deleted.readAsLinesSync()) {
          if (path.isNotEmpty) {
            File(p.join(root, path)).deleteSync();
          }
        }
      }
      final File published = File(p.join(root, '.published.yaml'))
        ..writeAsStringSync(
          File(
            p.join(fixture.directory, 'published.yaml'),
          ).readAsStringSync().replaceAll('BASE', base),
        );

      final StringBuffer out = StringBuffer();
      final int code = runVersionCheck(root, published.path, out);
      expect(code, fixture.expectedExitCode, reason: '$out');
      for (final String text in fixture.expectedOutput) {
        expect('$out', contains(text));
      }
    });
  }

  group('published.yaml', () {
    test('parses rows', () {
      final Map<String, PublishedRow> rows = parsePublished(
        'packages:\n  a:\n    version: 0.1.0\n    commit: abc\n',
      );
      expect(rows['a']!.version, Version(0, 1, 0));
      expect(rows['a']!.commit, 'abc');
    });

    test('refuses a row without a commit', () {
      expect(
        () => parsePublished('packages:\n  a:\n    version: 0.1.0\n'),
        throwsFormatException,
      );
    });

    test('the checked-in file parses and names only existing packages', () {
      final Map<String, PublishedRow> rows = parsePublished(
        File('published.yaml').readAsStringSync(),
      );
      expect(rows, isNotEmpty);
      for (final PublishedRow row in rows.values) {
        expect(
          File(
            p.join('..', 'packages', row.package, 'pubspec.yaml'),
          ).existsSync(),
          isTrue,
          reason: row.package,
        );
        expect(row.version.isPreRelease, isFalse, reason: row.package);
        expect(row.commit, matches(RegExp(r'^[0-9a-f]{40}$')));
      }
    });
  });

  test('changedPaths finds added, removed and changed files', () {
    expect(
      changedPaths(
        <String, String>{'a': '1', 'b': '2', 'c': '3'},
        <String, String>{'a': '1', 'b': '9', 'd': '4'},
      ),
      <String>['b', 'c', 'd'],
    );
  });
}
