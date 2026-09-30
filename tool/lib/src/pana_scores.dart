// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// pana in the weekly job (spec 0006 criteria 17 and 17a, change plan
/// M245).
///
/// pana scores six platforms and watchOS is not one of them, so a package
/// that declares only `watchos:` loses the 20 "Platform support" points:
/// 140/160 is its ceiling (AUTHORING.md section 4). Every other section must
/// be full. A package that declares a platform pana scores, such as
/// flutter_watch_link with its `ios:`, must keep all 160.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'forbidden_words.dart';
import 'public_log.dart';

/// The platforms pana scores, as pubspec platform keys.
const Set<String> panaPlatforms = <String>{
  'android',
  'ios',
  'linux',
  'macos',
  'web',
  'windows',
};

/// The id of pana's "Platform support" section.
const String platformSectionId = 'platform';

/// The platforms pana scores that the pubspec [contents] declares under
/// `flutter.plugin.platforms`.
Set<String> scoredPlatforms(String contents) {
  final Object? pubspec = loadYaml(contents);
  final Object? flutter = pubspec is YamlMap ? pubspec['flutter'] : null;
  final Object? plugin = flutter is YamlMap ? flutter['plugin'] : null;
  final Object? platforms = plugin is YamlMap ? plugin['platforms'] : null;
  if (platforms is! YamlMap) {
    return <String>{};
  }
  return platforms.keys
      .map((Object? key) => '$key')
      .where(panaPlatforms.contains)
      .toSet();
}

/// One section of a pana report.
class PanaSection {
  /// Creates a section.
  const PanaSection(
    this.id,
    this.title,
    this.granted,
    this.max,
    this.failedChecks,
  );

  /// pana's id for the section, such as `platform`.
  final String id;

  /// The title pub.dev shows.
  final String title;

  /// The points the package got.
  final int granted;

  /// The points the section can give.
  final int max;

  /// The headings of the checks in the section that lost points.
  final List<String> failedChecks;
}

/// The parts of a `pana --json` report that the check reads.
class PanaReport {
  /// Creates a report.
  const PanaReport(
    this.packageName,
    this.panaVersion,
    this.sections,
    this.granted,
    this.max,
  );

  /// Parses the output of `pana --json`.
  ///
  /// Throws a [FormatException] when a part the check needs is missing.
  factory PanaReport.parse(String json) {
    final Object? document = jsonDecode(json);
    if (document is! Map<String, Object?>) {
      throw const FormatException('The report is not a JSON object.');
    }
    final Object? runtime = document['runtimeInfo'];
    final Object? report = document['report'];
    final Object? sections = report is Map<String, Object?>
        ? report['sections']
        : null;
    final Object? scores = document['scores'];
    if (sections is! List<Object?> || scores is! Map<String, Object?>) {
      throw const FormatException('The report has no sections or scores.');
    }
    return PanaReport(
      '${document['packageName']}',
      runtime is Map<String, Object?> ? '${runtime['panaVersion']}' : '?',
      <PanaSection>[
        for (final Object? section in sections)
          if (section is Map<String, Object?>)
            PanaSection(
              '${section['id']}',
              '${section['title']}',
              section['grantedPoints'] as int,
              section['maxPoints'] as int,
              '${section['summary'] ?? ''}'
                  .split('\n')
                  .where(
                    (String line) =>
                        line.startsWith('### [x]') ||
                        line.startsWith('### [~]'),
                  )
                  .map((String line) => line.substring(4))
                  .toList(),
            ),
      ],
      scores['grantedPoints'] as int,
      scores['maxPoints'] as int,
    );
  }

  /// The package the report is about.
  final String packageName;

  /// The pana version that wrote the report.
  final String panaVersion;

  /// The report's sections.
  final List<PanaSection> sections;

  /// The points the package got.
  final int granted;

  /// The points pana can give.
  final int max;
}

/// The problems of [report] for a package that declares the pana
/// [platforms]: every section is full, except "Platform support" when
/// [platforms] is empty, which must then be 0.
List<String> comparePana(PanaReport report, Set<String> platforms) {
  final List<String> problems = <String>[];
  for (final PanaSection section in report.sections) {
    final bool watchosOnly = platforms.isEmpty;
    if (section.id == platformSectionId && watchosOnly) {
      if (section.granted != 0) {
        problems.add(
          '${section.title}: ${section.granted}/${section.max} for a '
          'watchOS-only package. AUTHORING.md section 4 says pana cannot '
          'score watchOS; update it.',
        );
      }
      continue;
    }
    if (section.granted < section.max) {
      problems.add(
        '${section.title}: ${section.granted}/${section.max}'
        '${section.failedChecks.isEmpty ? '' : ':'}',
      );
      problems.addAll(section.failedChecks.map((String line) => '  $line'));
    }
  }
  return problems;
}

/// Compares the pana report `<package>.json` in [reports] of each package
/// of the repository at [root] with what the package declares, writes the
/// report to [out] and returns the exit code.
int runPanaScores(
  String root,
  String reports,
  ForbiddenWords words,
  StringSink out,
) {
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
  int failures = 0;
  for (final String package in packages) {
    final ReportEntry entry = ReportEntry(package);
    final File file = File(p.join(reports, '$package.json'));
    if (!file.existsSync() || file.lengthSync() == 0) {
      entry.problems.add('pana wrote no report; see its log.');
    } else {
      try {
        final PanaReport report = PanaReport.parse(file.readAsStringSync());
        if (report.packageName != package) {
          entry.problems.add('The report is about ${report.packageName}.');
        }
        entry.problems.addAll(
          comparePana(
            report,
            scoredPlatforms(
              File(
                p.join(root, 'packages', package, 'pubspec.yaml'),
              ).readAsStringSync(),
            ),
          ),
        );
        entry.summary =
            '${report.granted}/${report.max} (pana ${report.panaVersion})';
        if (entry.problems.isNotEmpty) {
          entry.notes.add(entry.summary);
        }
      } on FormatException catch (error) {
        entry.problems.add('The report does not parse: ${error.message}');
      } on TypeError {
        entry.problems.add(
          'The report does not parse: a points value is not '
          'a number.',
        );
      }
    }
    if (entry.writeTo(out, words)) {
      failures++;
    }
  }
  if (failures > 0) {
    out.writeln('pana: $failures of ${packages.length} packages lose points.');
    return 1;
  }
  out.writeln(
    'pana: all ${packages.length} packages lose points only for watchOS.',
  );
  return 0;
}
