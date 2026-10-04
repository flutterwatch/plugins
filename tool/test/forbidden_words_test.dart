// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The word rule in Dart and in the shell give the same answers.
//
// The samples live in tool/words/samples.txt, because this file is itself
// checked by the rule and may not spell the words out.

import 'dart:io';

import 'package:plugins_tool/src/forbidden_words.dart';
import 'package:test/test.dart';

/// A sample line and whether the rule should find a word in it.
class _Sample {
  const _Sample(this.text, this.isHit);

  final String text;
  final bool isHit;
}

List<_Sample> _loadSamples() {
  return File('words/samples.txt')
      .readAsLinesSync()
      .where((String line) => line.isNotEmpty && !line.startsWith('#'))
      .map((String line) {
        final int tab = line.indexOf('\t');
        return _Sample(
          line.substring(tab + 1),
          line.substring(0, tab) == 'hit',
        );
      })
      .toList();
}

void main() {
  final ForbiddenWords words = ForbiddenWords.load('words/words.txt');
  final List<_Sample> samples = _loadSamples();

  test('the list has seven words', () {
    expect(words.words, hasLength(7));
  });

  test('the samples cover both answers', () {
    expect(samples.where((_Sample s) => s.isHit), isNotEmpty);
    expect(samples.where((_Sample s) => !s.isHit), isNotEmpty);
  });

  test('the Dart rule gives each sample its expected answer', () {
    for (final _Sample sample in samples) {
      expect(
        words.wordsIn(sample.text).isNotEmpty,
        sample.isHit,
        reason: sample.text,
      );
    }
  });

  test('the shell form gives the same answers as the Dart rule', () async {
    // Each line starts with its index and a colon. Digits and the colon
    // separate words, so the prefix changes no answer.
    final Process process = await Process.start('bash', <String>[
      'check_words.sh',
      '--filter',
    ]);
    process.stdin.write(
      <String>[
        for (int i = 0; i < samples.length; i++) '$i:${samples[i].text}\n',
      ].join(),
    );
    await process.stdin.close();
    final String output = await process.stdout
        .transform(const SystemEncoding().decoder)
        .join();
    expect(await process.exitCode, 0);
    final Set<int> shellHits = output
        .split('\n')
        .where((String line) => line.isNotEmpty)
        .map((String line) => int.parse(line.substring(0, line.indexOf(':'))))
        .toSet();
    final Set<int> dartHits = <int>{
      for (int i = 0; i < samples.length; i++)
        if (words.wordsIn(samples[i].text).isNotEmpty) i,
    };
    expect(dartHits, isNotEmpty);
    expect(shellHits, dartHits);
  });

  test('camelCase and snake_case split into words', () {
    expect(ForbiddenWords.ruleWords('rawValue'), <String>['raw', 'Value']);
    expect(ForbiddenWords.ruleWords('not_in_set'), <String>[
      'not',
      'in',
      'set',
    ]);
    expect(ForbiddenWords.ruleWords('v0.1.0-rc.2'), <String>['v', 'rc']);
  });

  group('entry lists', () {
    test('parse glob, text and reason', () {
      final WordEntries entries = WordEntries.parse(
        '# a comment\n\nlib/a.dart | x.y( | a call\n',
      );
      expect(entries.entries, hasLength(1));
      expect(entries.entries.single.line, 3);
      expect(entries.entries.single.text, 'x.y(');
      expect(entries.entries.single.reason, 'a call');
    });

    test('refuse a line without a reason', () {
      expect(
        () => WordEntries.parse('lib/a.dart | x.y(\n'),
        throwsFormatException,
      );
      expect(
        () => WordEntries.parse('lib/a.dart | x.y( |   \n'),
        throwsFormatException,
      );
    });

    test('apply only where their glob matches', () {
      final WordEntries entries = WordEntries.parse(
        'packages/*/lib/*.dart | x.y( | a call\n',
      );
      expect(
        entries.covering('packages/a/lib/b.dart', 'z = x.y(1)'),
        isNotNull,
      );
      expect(entries.covering('packages/a/test/b.dart', 'z = x.y(1)'), isNull);
      expect(entries.covering('packages/a/lib/b.dart', 'z = x.z(1)'), isNull);
    });

    test('globs match the paths they name', () {
      expect(globToRegExp('a/*.dart').hasMatch('a/b.dart'), isTrue);
      expect(globToRegExp('a/*.dart').hasMatch('a/b/c.dart'), isFalse);
      expect(globToRegExp('packages/**').hasMatch('packages/a/b/c'), isTrue);
      expect(globToRegExp('**/ci.yml').hasMatch('ci.yml'), isTrue);
      expect(
        globToRegExp('**/ci.yml').hasMatch('.github/workflows/ci.yml'),
        isTrue,
      );
      expect(globToRegExp('lib/a?.dart').hasMatch('lib/ab.dart'), isTrue);
      expect(globToRegExp('lib/a.dart').hasMatch('lib/a_dart'), isFalse);
    });
  });
}
