// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The version check (spec 0006 criterion 4, change plan M178).
///
/// `tool/published.yaml` records, per package, the last version on pub.dev
/// and the commit it was published from. A package whose publishable files
/// differ from that commit's needs a higher version than the recorded one,
/// and a top CHANGELOG heading equal to it. No package may be at a
/// pre-release. A package without a row has never been published; it gets
/// the last two checks only.
///
/// A Dart file that differs only in formatting does not count as changed:
/// the published copy, run through the formatter at the package's language
/// version, is byte for byte the file in the tree. A format-only commit then
/// ships with each package's next version (spec 0007 criterion 32) instead of
/// forcing a release of every package it touches.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'published_files.dart';
import 'repository.dart';

/// One row of `tool/published.yaml`.
class PublishedRow {
  /// Creates a row.
  const PublishedRow(this.package, this.version, this.commit);

  /// The package name.
  final String package;

  /// The last version on pub.dev.
  final Version version;

  /// The commit that version was published from.
  final String commit;
}

/// Parses the `packages:` map of `tool/published.yaml`.
///
/// Throws a [FormatException] when a row lacks its version or commit.
Map<String, PublishedRow> parsePublished(String contents) {
  final Object? document = loadYaml(contents);
  final Object? packages = document is YamlMap ? document['packages'] : null;
  if (packages == null) {
    return <String, PublishedRow>{};
  }
  if (packages is! YamlMap) {
    throw const FormatException('"packages" must be a map.');
  }
  final Map<String, PublishedRow> rows = <String, PublishedRow>{};
  packages.forEach((Object? name, Object? value) {
    final Object? version = value is YamlMap ? value['version'] : null;
    final Object? commit = value is YamlMap ? value['commit'] : null;
    if (version is! String || commit is! String) {
      throw FormatException('$name needs a "version" and a "commit".');
    }
    rows['$name'] = PublishedRow('$name', Version.parse(version), commit);
  });
  return rows;
}

/// The `version:` of the pubspec in [packageDirectory].
Version pubspecVersion(String packageDirectory) {
  final Object? pubspec = loadYaml(
    File(p.join(packageDirectory, 'pubspec.yaml')).readAsStringSync(),
  );
  final Object? version = pubspec is YamlMap ? pubspec['version'] : null;
  if (version is! String) {
    throw FormatException('$packageDirectory/pubspec.yaml has no version.');
  }
  return Version.parse(version);
}

/// The text of the first `## ` heading of the CHANGELOG in
/// [packageDirectory], or null when there is none.
String? topChangelogHeading(String packageDirectory) {
  final File changelog = File(p.join(packageDirectory, 'CHANGELOG.md'));
  if (!changelog.existsSync()) {
    return null;
  }
  for (final String line in changelog.readAsLinesSync()) {
    if (line.startsWith('## ')) {
      return line.substring(3).trim();
    }
  }
  return null;
}

/// What the check found for one package.
class PackageVersionResult {
  /// Creates a result.
  PackageVersionResult(this.package, this.version);

  /// The package name.
  final String package;

  /// The pubspec version.
  final Version version;

  /// Problems; empty when the package passes.
  final List<String> problems = <String>[];

  /// Remarks that do not fail the check.
  final List<String> notes = <String>[];
}

/// Checks every package under `packages/` of the repository at [root]
/// against [rows]. A row for a package that does not exist is reported
/// under the name `(published.yaml)`.
List<PackageVersionResult> checkVersions(
  String root,
  Map<String, PublishedRow> rows,
) {
  final List<PackageVersionResult> results = <PackageVersionResult>[];
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
    final String directory = p.join(root, 'packages', package);
    final Version version = pubspecVersion(directory);
    final PackageVersionResult result = PackageVersionResult(package, version);
    results.add(result);

    if (version.isPreRelease) {
      result.problems.add('$version is a pre-release.');
    }
    final String? heading = topChangelogHeading(directory);
    if (heading != '$version') {
      result.problems.add(
        heading == null
            ? 'CHANGELOG.md has no "## $version" heading.'
            : 'The top CHANGELOG heading is "$heading", not "$version".',
      );
    }

    final PublishedRow? row = rows[package];
    if (row == null) {
      result.notes.add('Not in tool/published.yaml: checked as unpublished.');
      continue;
    }
    if (!_commitExists(root, row.commit)) {
      result.problems.add(
        'Commit ${row.commit} of tool/published.yaml is not in this clone '
        '(a shallow checkout?).',
      );
      continue;
    }
    if (version < row.version) {
      result.problems.add(
        '$version is lower than the published ${row.version}.',
      );
      continue;
    }
    final Map<String, String> before = publishedFilesAt(
      root,
      row.commit,
      package,
    );
    final List<String> changed = changedPaths(
      before,
      publishedFilesInWorkingTree(root, package),
    );
    final Set<String> formatOnly = changed.isNotEmpty && version == row.version
        ? formatOnlyChanges(root, directory, changed, before)
        : const <String>{};
    final List<String> real = changed
        .where((String path) => !formatOnly.contains(path))
        .toList();
    if (real.isNotEmpty && version == row.version) {
      final String shown = real.take(5).join(', ');
      final String more = real.length > 5 ? ' and ${real.length - 5} more' : '';
      result.problems.add(
        '${real.length} publishable files changed since ${row.version} '
        '(${row.commit.substring(0, 7)}), but the version is still $version: '
        '$shown$more.',
      );
    }
    if (formatOnly.isNotEmpty) {
      result.notes.add(
        '${formatOnly.length} publishable files changed only in formatting '
        'since ${row.version}; they ship with the next version.',
      );
    }
    if (changed.isEmpty && version != row.version) {
      result.notes.add(
        'The version moved to $version with no publishable change.',
      );
    }
  }

  for (final String package in rows.keys) {
    if (!packages.contains(package)) {
      final PackageVersionResult stale = PackageVersionResult(
        '(published.yaml)',
        Version.none,
      );
      stale.problems.add('Row "$package" names no package under packages/.');
      results.add(stale);
    }
  }
  return results;
}

/// The paths in [changed] whose only difference from the published commit
/// is formatting.
///
/// A path counts when it is a Dart file present both in [before] (path to
/// blob id, as [publishedFilesAt] returns) and in the working tree, and the
/// formatter turns the published blob into exactly the file in the tree. It
/// formats at the language version of the package in [packageDirectory], the
/// lower bound of its SDK constraint, which is the one pub writes into the
/// package config and so the one `dart format` uses there. A blob the
/// formatter cannot parse is a real change.
Set<String> formatOnlyChanges(
  String root,
  String packageDirectory,
  Iterable<String> changed,
  Map<String, String> before,
) {
  final String? languageVersion = packageLanguageVersion(packageDirectory);
  final Set<String> formatOnly = <String>{};
  for (final String path in changed) {
    final String? blob = before[path];
    final File current = File(p.join(root, path));
    if (!path.endsWith('.dart') || blob == null || !current.existsSync()) {
      continue;
    }
    final String? formatted = formatDart(
      git(root, <String>['cat-file', 'blob', blob]),
      languageVersion,
    );
    if (formatted != null && formatted == current.readAsStringSync()) {
      formatOnly.add(path);
    }
  }
  return formatOnly;
}

/// The language version of the package in [packageDirectory]: the
/// `major.minor` of the lower bound of its `environment: sdk:` constraint, or
/// null when the pubspec gives none.
String? packageLanguageVersion(String packageDirectory) {
  final Object? pubspec = loadYaml(
    File(p.join(packageDirectory, 'pubspec.yaml')).readAsStringSync(),
  );
  final Object? environment = pubspec is YamlMap
      ? pubspec['environment']
      : null;
  final Object? sdk = environment is YamlMap ? environment['sdk'] : null;
  if (sdk is! String) {
    return null;
  }
  final VersionConstraint constraint = VersionConstraint.parse(sdk);
  final Version? min = constraint is VersionRange ? constraint.min : null;
  return min == null ? null : '${min.major}.${min.minor}';
}

/// [source] as `dart format` writes it at [languageVersion] (the formatter's
/// default when null), or null when the formatter refuses it.
///
/// It runs the formatter of the Dart SDK this tool runs on, the one CI pins.
String? formatDart(String source, String? languageVersion) {
  final String dart = Platform.resolvedExecutable;
  final Directory scratch = Directory.systemTemp.createTempSync(
    'plugins_tool_format_',
  );
  try {
    // A file rather than stdin, which runSync cannot feed. Its name decides
    // nothing, because the language version is passed. --summary=none keeps
    // the "Formatted 1 file" line out of the source on stdout.
    final File file = File(p.join(scratch.path, 'source.dart'))
      ..writeAsStringSync(source);
    final ProcessResult result = Process.runSync(dart, <String>[
      'format',
      '--output=show',
      '--summary=none',
      if (languageVersion != null) '--language-version=$languageVersion',
      file.path,
    ]);
    return result.exitCode == 0 ? result.stdout as String : null;
  } finally {
    scratch.deleteSync(recursive: true);
  }
}

bool _commitExists(String root, String commit) {
  final ProcessResult result = Process.runSync('git', <String>[
    'cat-file',
    '-e',
    '$commit^{commit}',
  ], workingDirectory: root);
  return result.exitCode == 0;
}

/// Runs the check on the repository at [root] with the rows in
/// [publishedFile], writes the report to [out] and returns the exit code.
int runVersionCheck(String root, String publishedFile, StringSink out) {
  final List<PackageVersionResult> results = checkVersions(
    root,
    parsePublished(File(publishedFile).readAsStringSync()),
  );
  int failures = 0;
  for (final PackageVersionResult result in results) {
    final bool ok = result.problems.isEmpty;
    if (!ok) {
      failures++;
    }
    out.writeln('${ok ? 'ok  ' : 'FAIL'} ${result.package} ${result.version}');
    for (final String problem in result.problems) {
      out.writeln('       $problem');
    }
    for (final String note in result.notes) {
      out.writeln('       note: $note');
    }
  }
  if (failures > 0) {
    out.writeln(
      '$failures packages need a new version, a matching CHANGELOG heading '
      'or a plain version.',
    );
    return 1;
  }
  out.writeln('Versions: every package passes.');
  return 0;
}
