// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The README snippet check (spec 0006 Decision 1a and criterion 2, change
/// plan M176). It reads files only; it never calls pub.dev.
///
/// Every `yaml` code block with a `dependencies:` map in a package README or
/// the root README is an install snippet. In it:
///
/// - each constraint is a caret constraint on a plain version: no
///   placeholder such as `^<latest>`, and no `any`;
/// - a package of this repository must be admitted at its pubspec version;
/// - an upstream package must be admitted at its latest version in
///   `tool/upstream_versions.yaml`, so its major is the latest one; that
///   file may also allow one exact older constraint, with its reason.
///
/// A federated package's README has a snippet that names the package and its
/// upstream, and a paragraph that tells the reader to add the package
/// alongside the upstream one; so does the root README. `flutter_watch_link`
/// has no upstream: its README needs a snippet that names it.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'versions.dart';

/// An upstream package's latest version, and an older constraint the table
/// allows instead, if any.
class UpstreamTable {
  /// Creates a table.
  UpstreamTable(this.latest, this.exceptions);

  /// Parses `tool/upstream_versions.yaml`.
  ///
  /// Throws a [FormatException] for a version that does not parse, or for an
  /// exception without its constraint and reason.
  factory UpstreamTable.parse(String contents) {
    final Object? document = loadYaml(contents);
    final Map<String, Version> latest = <String, Version>{};
    final Map<String, String> exceptions = <String, String>{};
    if (document is YamlMap) {
      final Object? upstreams = document['upstreams'];
      if (upstreams is YamlMap) {
        upstreams.forEach((Object? name, Object? version) {
          latest['$name'] = Version.parse('$version');
        });
      }
      final Object? listed = document['exceptions'];
      if (listed is YamlMap) {
        listed.forEach((Object? name, Object? value) {
          final Object? constraint = value is YamlMap
              ? value['constraint']
              : null;
          final Object? reason = value is YamlMap ? value['reason'] : null;
          if (constraint is! String || reason is! String || reason.isEmpty) {
            throw FormatException(
              'Exception "$name" needs a "constraint" and a "reason".',
            );
          }
          exceptions['$name'] = constraint;
        });
      }
    }
    return UpstreamTable(latest, exceptions);
  }

  /// The latest version of each upstream package.
  final Map<String, Version> latest;

  /// An older constraint each package may also use, by package.
  final Map<String, String> exceptions;
}

/// One dependency line of an install snippet.
class SnippetDependency {
  /// Creates a dependency read from the block whose content starts at
  /// [line].
  const SnippetDependency(this.name, this.constraint, this.line);

  /// The package name.
  final String name;

  /// The constraint as written: a string, null for an empty value, or a map.
  final Object? constraint;

  /// The line where the block's content starts, from 1.
  final int line;
}

/// The fenced code blocks of [markdown] whose info string is `yaml` and
/// whose YAML has a `dependencies` map. Throws a [FormatException] for such
/// a block that is not valid YAML.
List<List<SnippetDependency>> installSnippets(String markdown) {
  final List<List<SnippetDependency>> snippets = <List<SnippetDependency>>[];
  final List<String> lines = markdown.split('\n');
  for (int i = 0; i < lines.length; i++) {
    final String fence = lines[i].trim();
    if (!fence.startsWith('```') || fence.substring(3).trim() != 'yaml') {
      continue;
    }
    final int start = i + 1;
    int end = start;
    while (end < lines.length && !lines[end].trim().startsWith('```')) {
      end++;
    }
    final String body = lines.sublist(start, end).join('\n');
    i = end;
    if (!RegExp(r'^\s*dependencies:', multiLine: true).hasMatch(body)) {
      continue;
    }
    final Object? document;
    try {
      document = loadYaml(body);
    } on YamlException catch (error) {
      throw FormatException(
        'The yaml block at line ${start + 1} does not parse: ${error.message}',
      );
    }
    final Object? dependencies = document is YamlMap
        ? document['dependencies']
        : null;
    if (dependencies is! YamlMap) {
      continue;
    }
    snippets.add(<SnippetDependency>[
      for (final MapEntry<Object?, Object?> entry in dependencies.entries)
        SnippetDependency('${entry.key}', entry.value, start + 1),
    ]);
  }
  return snippets;
}

/// Whether some paragraph of [markdown], outside code blocks, tells the
/// reader to add something alongside something else: it holds a form of
/// "add" and the word "alongside".
bool hasAlongsideSentence(String markdown) {
  final RegExp add = RegExp(r'\badd(s|ed|ing)?\b', caseSensitive: false);
  final RegExp alongside = RegExp(r'\balongside\b', caseSensitive: false);
  final StringBuffer paragraph = StringBuffer();
  bool inCode = false;
  bool found = false;
  void flush() {
    final String text = paragraph.toString();
    if (add.hasMatch(text) && alongside.hasMatch(text)) {
      found = true;
    }
    paragraph.clear();
  }

  for (final String line in markdown.split('\n')) {
    if (line.trim().startsWith('```')) {
      flush();
      inCode = !inCode;
      continue;
    }
    if (inCode) {
      continue;
    }
    if (line.trim().isEmpty) {
      flush();
    } else {
      paragraph
        ..write(line)
        ..write(' ');
    }
  }
  flush();
  return found;
}

/// The problems with one dependency of a snippet, given the repository's
/// package versions and the upstream table.
List<String> checkDependency(
  SnippetDependency dependency,
  Map<String, Version> repositoryPackages,
  UpstreamTable table,
) {
  final String where = 'line ${dependency.line}, ${dependency.name}';
  final Object? value = dependency.constraint;
  if (value == null || (value is String && value.trim() == 'any')) {
    return <String>['$where: "any" hides the major it needs; use ^x.y.z.'];
  }
  if (value is! String) {
    return <String>['$where: not a version constraint.'];
  }
  final String text = value.trim();
  if (text.contains('<') && text.contains('>') && !text.contains(' ')) {
    return <String>['$where: "$text" is a placeholder; use ^x.y.z.'];
  }
  final VersionConstraint constraint;
  try {
    constraint = VersionConstraint.parse(text);
  } on FormatException {
    return <String>['$where: "$text" is not a version constraint.'];
  }
  if (!text.startsWith('^')) {
    return <String>['$where: "$text" is not a caret constraint.'];
  }
  if ((constraint as VersionRange).min!.isPreRelease) {
    return <String>['$where: "$text" names a pre-release.'];
  }

  final Version? own = repositoryPackages[dependency.name];
  if (own != null) {
    return constraint.allows(own)
        ? <String>[]
        : <String>['$where: "$text" does not admit its pubspec version $own.'];
  }
  if (table.exceptions[dependency.name] == text) {
    return <String>[];
  }
  final Version? latest = table.latest[dependency.name];
  if (latest == null) {
    return <String>[
      '$where: not a package here and not in tool/upstream_versions.yaml.',
    ];
  }
  return constraint.allows(latest)
      ? <String>[]
      : <String>[
          '$where: "$text" does not admit the latest version $latest '
              '(major ${latest.major}).',
        ];
}

/// The problems of each checked README of the repository at [root], by its
/// repository-relative path. A README without problems maps to an empty
/// list.
Map<String, List<String>> checkReadmes(String root, UpstreamTable table) {
  final Map<String, Version> versions = <String, Version>{};
  final List<String> packages =
      Directory(p.join(root, 'packages'))
          .listSync()
          .whereType<Directory>()
          .where(
            (Directory d) => File(p.join(d.path, 'pubspec.yaml')).existsSync(),
          )
          .map((Directory d) => p.basename(d.path))
          .toList()
        ..sort();
  for (final String package in packages) {
    versions[package] = pubspecVersion(p.join(root, 'packages', package));
  }

  final Map<String, List<String>> results = <String, List<String>>{};
  List<String> check(String path, {required List<String> mustName}) {
    final List<String> problems = <String>[];
    final File file = File(p.join(root, path));
    if (!file.existsSync()) {
      return <String>['There is no README.'];
    }
    final String markdown = file.readAsStringSync();
    final List<List<SnippetDependency>> snippets;
    try {
      snippets = installSnippets(markdown);
    } on FormatException catch (error) {
      return <String>[error.message];
    }
    for (final List<SnippetDependency> snippet in snippets) {
      for (final SnippetDependency dependency in snippet) {
        problems.addAll(checkDependency(dependency, versions, table));
      }
    }
    final bool named = snippets.any(
      (List<SnippetDependency> snippet) => mustName.every(
        (String name) => snippet.any((SnippetDependency d) => d.name == name),
      ),
    );
    if (!named) {
      problems.add(
        'No install snippet names ${mustName.join(' and ')} together.',
      );
    }
    return problems;
  }

  for (final String package in packages) {
    final String path = 'packages/$package/README.md';
    if (package.endsWith('_watchos')) {
      final String upstream = package.substring(
        0,
        package.length - '_watchos'.length,
      );
      final List<String> problems = check(
        path,
        mustName: <String>[upstream, package],
      );
      final File readme = File(p.join(root, path));
      if (readme.existsSync() &&
          !hasAlongsideSentence(readme.readAsStringSync())) {
        problems.add(
          'No sentence tells the reader to add $package alongside $upstream.',
        );
      }
      results[path] = problems;
    } else {
      results[path] = check(path, mustName: <String>[package]);
    }
  }

  final File rootReadme = File(p.join(root, 'README.md'));
  if (rootReadme.existsSync()) {
    final List<String> problems = <String>[];
    final List<List<SnippetDependency>> snippets;
    try {
      snippets = installSnippets(rootReadme.readAsStringSync());
      for (final List<SnippetDependency> snippet in snippets) {
        for (final SnippetDependency dependency in snippet) {
          problems.addAll(checkDependency(dependency, versions, table));
        }
      }
      if (snippets.isEmpty) {
        problems.add('No install snippet.');
      }
    } on FormatException catch (error) {
      problems.add(error.message);
    }
    if (!hasAlongsideSentence(rootReadme.readAsStringSync())) {
      problems.add(
        'No sentence tells the reader to add a *_watchos package alongside '
        'its upstream.',
      );
    }
    results['README.md'] = problems;
  }
  return results;
}

/// Runs the check on the repository at [root] with the table in
/// [tableFile], writes the report to [out] and returns the exit code.
int runSnippetCheck(String root, String tableFile, StringSink out) {
  final Map<String, List<String>> results = checkReadmes(
    root,
    UpstreamTable.parse(File(tableFile).readAsStringSync()),
  );
  int failures = 0;
  for (final MapEntry<String, List<String>> entry in results.entries) {
    if (entry.value.isEmpty) {
      out.writeln('ok   ${entry.key}');
      continue;
    }
    failures++;
    out.writeln('FAIL ${entry.key}');
    for (final String problem in entry.value) {
      out.writeln('       $problem');
    }
  }
  if (failures > 0) {
    out.writeln('$failures READMEs need a fixed install snippet or sentence.');
    return 1;
  }
  out.writeln('README snippets: all ${results.length} pass.');
  return 0;
}
