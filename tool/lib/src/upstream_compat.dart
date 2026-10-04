// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The weekly upstream compatibility check (spec 0006 Decision 7 and
/// criterion 17a, change plan M244).
///
/// An upstream plugin moves on without us: a new major can drop the
/// platform interface version a `*_watchos` package implements, and then
/// the README's install snippet stops resolving (plugins.md P6, found by
/// hand). Each week, for every federated package, this check
///
/// - compares pub.dev's latest upstream version with
///   `tool/upstream_versions.yaml`, which the README snippets follow: a new
///   major there fails;
/// - resolves a scratch app with the upstream at its latest version and the
///   package from this repository, and another with the package's latest
///   version on pub.dev, as a user would; either failing to resolve fails.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'forbidden_words.dart';
import 'public_log.dart';
import 'readme_snippets.dart';

/// Returns a package's latest version on pub.dev, or null when pub.dev does
/// not know the package.
typedef LatestVersionFetcher = Future<Version?> Function(String package);

/// What `pub get` printed in a scratch app, and its exit code.
typedef Resolution = ({int exitCode, String output});

/// Runs `pub get` in the scratch app in a directory.
typedef Resolver = Resolution Function(String appDirectory);

/// The latest version in a response of the pub.dev API
/// (`GET /api/packages/<name>`).
Version latestVersionFromApi(String json) {
  final Object? document = jsonDecode(json);
  final Object? latest = document is Map<String, Object?>
      ? document['latest']
      : null;
  final Object? version = latest is Map<String, Object?>
      ? latest['version']
      : null;
  if (version is! String) {
    throw const FormatException('The response has no latest.version.');
  }
  return Version.parse(version);
}

/// A [LatestVersionFetcher] that reads the pub.dev API at [host] through
/// [client].
LatestVersionFetcher pubDevFetcher(
  HttpClient client, {
  String host = 'https://pub.dev',
}) {
  return (String package) async {
    final HttpClientRequest request = await client.getUrl(
      Uri.parse('$host/api/packages/$package'),
    );
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.pub.v2+json',
    );
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.notFound) {
      return null;
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'pub.dev answered ${response.statusCode} for $package.',
      );
    }
    return latestVersionFromApi(body);
  };
}

/// A [Resolver] that runs `flutter pub get`.
Resolver flutterPubGet({String flutter = 'flutter'}) {
  return (String appDirectory) {
    final ProcessResult result = Process.runSync(flutter, <String>[
      'pub',
      'get',
    ], workingDirectory: appDirectory);
    return (
      exitCode: result.exitCode,
      output: '${result.stdout}\n${result.stderr}',
    );
  };
}

/// The upstream each federated package of the repository at [root]
/// implements (its pubspec's `flutter.plugin.implements`), by package.
Map<String, String> implementedUpstreams(String root) {
  final Map<String, String> upstreams = <String, String>{};
  final List<Directory> packages =
      Directory(p.join(root, 'packages'))
          .listSync()
          .whereType<Directory>()
          .where(
            (Directory d) => File(p.join(d.path, 'pubspec.yaml')).existsSync(),
          )
          .toList()
        ..sort((Directory a, Directory b) => a.path.compareTo(b.path));
  for (final Directory package in packages) {
    final Object? pubspec = loadYaml(
      File(p.join(package.path, 'pubspec.yaml')).readAsStringSync(),
    );
    final Object? flutter = pubspec is YamlMap ? pubspec['flutter'] : null;
    final Object? plugin = flutter is YamlMap ? flutter['plugin'] : null;
    final Object? implements = plugin is YamlMap ? plugin['implements'] : null;
    if (implements is String) {
      upstreams[p.basename(package.path)] = implements;
    }
  }
  return upstreams;
}

/// Compares the table's latest version of [upstream] with pub.dev's.
///
/// Returns a problem when they name different majors, or when either is
/// missing; a note when pub.dev has a newer version of the same major; and
/// nothing when they are equal.
({String? problem, String? note}) compareWithTable(
  String upstream,
  Version? table,
  Version? pubDev,
) {
  if (table == null) {
    return (
      problem: '$upstream is not in tool/upstream_versions.yaml.',
      note: null,
    );
  }
  if (pubDev == null) {
    return (problem: 'pub.dev has no version of $upstream.', note: null);
  }
  if (pubDev >= table.nextBreaking) {
    return (
      problem:
          'pub.dev has $upstream $pubDev, a new major; '
          'tool/upstream_versions.yaml and the README snippets say $table. '
          'Check the package against it, then move both.',
      note: null,
    );
  }
  if (pubDev < table) {
    return (
      problem:
          "pub.dev's latest $upstream is $pubDev, older than $table in "
          'tool/upstream_versions.yaml.',
      note: null,
    );
  }
  if (pubDev > table) {
    return (
      problem: null,
      note:
          'pub.dev has $upstream $pubDev; tool/upstream_versions.yaml says '
          '$table (the same major).',
    );
  }
  return (problem: null, note: null);
}

/// The pubspec of a scratch app that depends on [upstream] at
/// `^upstreamVersion` and on [package], from [packagePath] when it is
/// given, and otherwise at `^packageVersion` from pub.dev.
String scratchPubspec({
  required String upstream,
  required Version upstreamVersion,
  required String package,
  String? packagePath,
  Version? packageVersion,
}) {
  final String source = packagePath != null
      ? '\n    path: ${jsonEncode(packagePath)}'
      : ' ^$packageVersion';
  return 'name: upstream_compatibility\n'
      'publish_to: none\n'
      'environment:\n'
      '  sdk: ">=3.0.0 <4.0.0"\n'
      'dependencies:\n'
      '  flutter:\n'
      '    sdk: flutter\n'
      '  $upstream: ^$upstreamVersion\n'
      '  $package:$source\n';
}

/// The lines of a failed `pub get` that say why, without the progress
/// lines; at most [limit] of them.
List<String> resolutionReason(String output, {int limit = 8}) {
  return output
      .split('\n')
      .map((String line) => line.trim())
      .where(
        (String line) =>
            line.isNotEmpty &&
            line != 'Resolving dependencies...' &&
            line != 'Downloading packages...',
      )
      .take(limit)
      .toList();
}

/// Runs the check on the repository at [root] with the table in
/// [tableFile], writes the report to [out] and returns the exit code.
Future<int> runUpstreamCompatibility(
  String root,
  String tableFile,
  LatestVersionFetcher latestVersion,
  Resolver resolve,
  ForbiddenWords words,
  StringSink out,
) async {
  final UpstreamTable table = UpstreamTable.parse(
    File(tableFile).readAsStringSync(),
  );
  final Map<String, String> upstreams = implementedUpstreams(root);
  final Directory scratch = Directory.systemTemp.createTempSync(
    'upstream_compatibility_',
  );
  int failures = 0;
  try {
    for (final MapEntry<String, String> entry in upstreams.entries) {
      final String package = entry.key;
      final String upstream = entry.value;
      final ReportEntry report = ReportEntry(package);
      final Version? upstreamLatest;
      final Version? packageLatest;
      try {
        upstreamLatest = await latestVersion(upstream);
        packageLatest = await latestVersion(package);
      } on Exception catch (error) {
        report.problems.add('pub.dev could not be read: $error');
        if (report.writeTo(out, words)) {
          failures++;
        }
        continue;
      }
      final ({String? problem, String? note}) comparison = compareWithTable(
        upstream,
        table.latest[upstream],
        upstreamLatest,
      );
      if (comparison.problem != null) {
        report.problems.add(comparison.problem!);
      }
      if (comparison.note != null) {
        report.notes.add(comparison.note!);
      }
      if (upstreamLatest != null) {
        void tryResolve(String directory, String label, String pubspec) {
          final Directory app = Directory(
            p.join(scratch.path, package, directory),
          )..createSync(recursive: true);
          File(p.join(app.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
          final Resolution resolution = resolve(app.path);
          if (resolution.exitCode != 0) {
            report.problems.add(
              '$upstream ^$upstreamLatest does not resolve with $package '
              '$label:',
            );
            report.problems.addAll(
              resolutionReason(
                resolution.output,
              ).map((String line) => '  $line'),
            );
          }
        }

        tryResolve(
          'repository',
          'from this repository',
          scratchPubspec(
            upstream: upstream,
            upstreamVersion: upstreamLatest,
            package: package,
            packagePath: p.absolute(root, 'packages', package),
          ),
        );
        if (packageLatest == null) {
          report.problems.add('pub.dev has no version of $package.');
        } else {
          tryResolve(
            'published',
            '$packageLatest from pub.dev',
            scratchPubspec(
              upstream: upstream,
              upstreamVersion: upstreamLatest,
              package: package,
              packageVersion: packageLatest,
            ),
          );
        }
      }
      report.summary =
          '$upstream $upstreamLatest resolves with the package from this '
          'repository and with $packageLatest from pub.dev';
      if (report.writeTo(out, words)) {
        failures++;
      }
    }
  } finally {
    scratch.deleteSync(recursive: true);
  }
  if (failures > 0) {
    out.writeln(
      'Upstream compatibility: $failures of ${upstreams.length} packages '
      'need a look.',
    );
    return 1;
  }
  out.writeln(
    'Upstream compatibility: all ${upstreams.length} packages resolve with '
    'their latest upstream.',
  );
  return 0;
}
