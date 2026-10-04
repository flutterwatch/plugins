// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The test-name step of the word check (spec 0006 criterion 1, 0007 D8).
///
/// CI logs print every test and group name, so a name may not hold a
/// forbidden word. Names never use the allow-list. Only the pending list
/// (`tool/words/pending.txt`) may name one, until its package commit renames
/// it.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import 'forbidden_words.dart';
import 'repository.dart';

/// A test or group name found in Dart source.
class TestName {
  /// Creates a name found at [line] of its file.
  const TestName(this.line, this.text);

  /// The line of the call, from 1.
  final int line;

  /// The static text of the name. An interpolated value stands as a space.
  final String text;
}

/// A test or group name that holds a forbidden word.
class TestNameHit {
  /// Creates a hit.
  const TestNameHit(this.path, this.name, this.words, {this.pending});

  /// The repository-relative path of the file.
  final String path;

  /// The name.
  final TestName name;

  /// The forbidden words in the name.
  final List<String> words;

  /// The pending entry that names this hit, if any.
  final WordEntry? pending;

  @override
  String toString() =>
      '$path:${name.line}: ${words.join(', ')} in '
      '"${name.text}"';
}

/// Collects the first argument of every call that declares a test or a
/// group: `test`, `group`, `testWidgets`, and local wrappers whose names
/// start with `test` or `group`.
class _TestNameVisitor extends RecursiveAstVisitor<void> {
  _TestNameVisitor(this.lineInfo);

  final LineInfo lineInfo;
  final List<TestName> names = <TestName>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final String name = node.methodName.name;
    final NodeList<Argument> arguments = node.argumentList.arguments;
    if (node.target == null &&
        (name.startsWith('test') || name.startsWith('group')) &&
        arguments.isNotEmpty &&
        arguments.first is StringLiteral) {
      names.add(
        TestName(
          lineInfo.getLocation(node.offset).lineNumber,
          _literalText(arguments.first as StringLiteral),
        ),
      );
    }
    super.visitMethodInvocation(node);
  }

  static String _literalText(StringLiteral literal) {
    if (literal is AdjacentStrings) {
      return literal.strings.map(_literalText).join();
    }
    if (literal is StringInterpolation) {
      return literal.elements
          .map(
            (InterpolationElement element) =>
                element is InterpolationString ? element.value : ' ',
          )
          .join();
    }
    return literal.stringValue ?? '';
  }
}

/// The test and group names declared in [source].
List<TestName> testNamesIn(String source) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final _TestNameVisitor visitor = _TestNameVisitor(result.lineInfo);
  result.unit.accept(visitor);
  return visitor.names;
}

/// Whether [path] is a Dart file under a package's `test/` or its example's
/// `integration_test/`.
bool isTestSource(String path) {
  if (!path.endsWith('.dart')) {
    return false;
  }
  final List<String> parts = p.posix.split(path);
  if (parts.length < 4 || parts[0] != 'packages') {
    return false;
  }
  return parts[2] == 'test' ||
      (parts.length >= 5 &&
          parts[2] == 'example' &&
          parts[3] == 'integration_test');
}

/// Every name under `packages/*/test/` and
/// `packages/*/example/integration_test/` of the repository at [root] that
/// holds one of [words]. A hit that a [pending] entry names is returned with
/// that entry.
List<TestNameHit> checkTestNames(
  String root,
  ForbiddenWords words, {
  WordEntries? pending,
}) {
  final List<TestNameHit> hits = <TestNameHit>[];
  for (final String path in repositoryFiles(root, <String>['packages'])) {
    if (!isTestSource(path)) {
      continue;
    }
    final String source = File(p.join(root, path)).readAsStringSync();
    for (final TestName name in testNamesIn(source)) {
      final List<String> found = words.wordsIn(name.text);
      if (found.isNotEmpty) {
        hits.add(
          TestNameHit(
            path,
            name,
            found,
            pending: pending?.covering(path, name.text),
          ),
        );
      }
    }
  }
  return hits;
}

/// Runs the test-name step on the repository at [root], writes its report
/// to [out], and returns the exit code: 1 when a name that [pending] does
/// not name holds a forbidden word, else 0.
int runTestNameStep(
  String root,
  ForbiddenWords words,
  WordEntries pending,
  StringSink out,
) {
  final List<TestNameHit> hits = checkTestNames(root, words, pending: pending);
  final List<TestNameHit> failures = hits
      .where((TestNameHit hit) => hit.pending == null)
      .toList();
  final List<TestNameHit> waiting = hits
      .where((TestNameHit hit) => hit.pending != null)
      .toList();
  if (waiting.isNotEmpty) {
    out.writeln(
      '${waiting.length} test names wait on the pending list for their '
      'rename:',
    );
    for (final TestNameHit hit in waiting) {
      out.writeln('  ${hit.path}:${hit.name.line}');
    }
  }
  if (failures.isNotEmpty) {
    out.writeln(
      'Test and group names are printed in public CI logs. Rename these:',
    );
    for (final TestNameHit hit in failures) {
      out.writeln('  $hit');
    }
    return 1;
  }
  out.writeln(
    waiting.isEmpty
        ? 'Test and group names: no forbidden word.'
        : 'Test and group names: no forbidden word outside the pending list.',
  );
  return 0;
}
