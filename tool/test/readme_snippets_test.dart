// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The README snippet check on its fixtures, in
// tool/test/fixtures/readme_snippets/, each with its own upstream table.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_tool/src/readme_snippets.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'src/fixture_repo.dart';

void main() {
  final List<Fixture> fixtures = fixturesIn(
    p.join('test', 'fixtures', 'readme_snippets'),
  );

  test('there is a failing fixture of each kind', () {
    expect(
      fixtures.map((Fixture f) => f.name),
      containsAll(<String>[
        'placeholder',
        'any',
        'own_version_not_admitted',
        'old_upstream_major',
        'no_alongside',
        'root_readme',
      ]),
    );
  });

  for (final Fixture fixture in fixtures) {
    test('fixture ${fixture.name}', () {
      final String root = Directory.systemTemp
          .createTempSync('plugins_tool_readme_')
          .path;
      addTearDown(() => Directory(root).deleteSync(recursive: true));
      copyTree(p.join(fixture.directory, 'repo'), root);
      final StringBuffer out = StringBuffer();
      final int code = runSnippetCheck(
        root,
        p.join(fixture.directory, 'upstream_versions.yaml'),
        out,
      );
      expect(code, fixture.expectedExitCode, reason: '$out');
      for (final String text in fixture.expectedOutput) {
        expect('$out', contains(text));
      }
    });
  }

  group('snippets', () {
    test('are the yaml blocks with a dependencies map', () {
      const String markdown = '''
```yaml
dependencies:
  a: ^1.0.0
```

```yaml
flutter:
  uses-material-design: true
```

```sh
dependencies:
  b: ^1.0.0
```
''';
      final List<List<SnippetDependency>> snippets = installSnippets(markdown);
      expect(snippets, hasLength(1));
      expect(snippets.single.single.name, 'a');
      expect(snippets.single.single.line, 2);
    });

    test('that do not parse are reported', () {
      expect(
        () => installSnippets('```yaml\ndependencies:\n  a: [\n```\n'),
        throwsFormatException,
      );
    });
  });

  group('the alongside sentence', () {
    test('needs "add" and "alongside" in one paragraph', () {
      expect(hasAlongsideSentence('Add it alongside the plugin.'), isTrue);
      expect(
        hasAlongsideSentence(
          'Apps only need to add this\npackage alongside it:',
        ),
        isTrue,
      );
      expect(hasAlongsideSentence('It returns alongside the list.'), isFalse);
      expect(hasAlongsideSentence('Add it.\n\nAlongside, it runs.'), isFalse);
      expect(hasAlongsideSentence('```\nadd it alongside\n```\n'), isFalse);
    });
  });

  group('a dependency', () {
    final UpstreamTable table = UpstreamTable.parse(
      'upstreams:\n  up: 3.2.1\n',
    );
    final Map<String, Version> own = <String, Version>{
      'up_watchos': Version(0, 1, 0),
    };
    List<String> problems(String name, Object? constraint) =>
        checkDependency(SnippetDependency(name, constraint, 1), own, table);

    test('passes when it admits the version it must', () {
      expect(problems('up', '^3.0.0'), isEmpty);
      expect(problems('up', '^3.2.1'), isEmpty);
      expect(problems('up_watchos', '^0.1.0'), isEmpty);
    });

    test('fails for a constraint that cannot reach the latest version', () {
      expect(problems('up', '^3.3.0'), isNotEmpty);
      expect(problems('up', '^2.0.0'), isNotEmpty);
    });

    test('fails for a map, such as a path dependency', () {
      expect(problems('up', <String, String>{'path': '../up'}), isNotEmpty);
    });
  });

  test('an exception needs a reason', () {
    expect(
      () => UpstreamTable.parse('exceptions:\n  up:\n    constraint: ^2.0.0\n'),
      throwsFormatException,
    );
  });
}
