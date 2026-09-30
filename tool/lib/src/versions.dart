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
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'published_files.dart';

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
    final List<String> changed = changedPaths(
      publishedFilesAt(root, row.commit, package),
      publishedFilesInWorkingTree(root, package),
    );
    if (changed.isNotEmpty && version == row.version) {
      final String shown = changed.take(5).join(', ');
      final String more = changed.length > 5
          ? ' and ${changed.length - 5} more'
          : '';
      result.problems.add(
        '${changed.length} publishable files changed since ${row.version} '
        '(${row.commit.substring(0, 7)}), but the version is still $version: '
        '$shown$more.',
      );
    } else if (changed.isEmpty && version != row.version) {
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
