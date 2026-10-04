// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The publish dry-run report (spec 0007 criterion 32, change plan M165).
///
/// `dart pub publish --dry-run` runs in every package, and the report names
/// each package's warnings and errors, so that a package that pub would
/// warn about, or refuse, is caught before the publish round rather than
/// during it. The report is printed into a public CI log, so every line it
/// prints goes through the word rule of spec 0007 D8 first.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'forbidden_words.dart';

/// What one run of `dart pub publish --dry-run` printed, and its exit code.
typedef PubRun = ({int exitCode, String stdout, String stderr});

/// Runs `dart pub publish --dry-run` in a package directory.
typedef PubRunner = PubRun Function(String packageDirectory);

/// A [PubRunner] that runs [dart] (by default the Dart that runs this tool),
/// with [environment] added to this process's environment.
PubRunner dartPubRunner({String? dart, Map<String, String>? environment}) {
  return (String packageDirectory) {
    final ProcessResult result = Process.runSync(
      dart ?? Platform.resolvedExecutable,
      <String>['pub', 'publish', '--dry-run'],
      workingDirectory: packageDirectory,
      environment: environment,
    );
    return (
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  };
}

/// What pub reported for one package.
class DryRunResult {
  /// Creates a result.
  DryRunResult({
    required this.exitCode,
    required this.details,
    this.publishing,
    this.archiveSize,
    this.warnings,
    this.hints = 0,
    this.hasErrors = false,
  });

  /// Pub's exit code: 0 without warnings, 65 with warnings or errors.
  final int exitCode;

  /// The package name and version from pub's "Publishing" line, or null
  /// when pub did not get that far.
  final String? publishing;

  /// The size of the archive pub would upload, such as "60 KB", or null.
  final String? archiveSize;

  /// The number of warnings in pub's summary, or null when pub printed no
  /// summary (for example when it could not resolve the dependencies).
  final int? warnings;

  /// The number of hints in pub's summary.
  final int hints;

  /// Whether pub found an error, which blocks the publish.
  final bool hasErrors;

  /// The lines that explain a warning, a hint or a failure: pub's validation
  /// messages, or, when it printed none, what it wrote to stderr.
  final List<String> details;

  /// Whether the package would publish with 0 warnings.
  bool get passed => exitCode == 0 && warnings == 0 && !hasErrors;
}

final RegExp _publishing = RegExp(r'^Publishing (\S+) (\S+) to \S+:$');
final RegExp _archiveSize = RegExp(r'^Total compressed archive size: (.+)\.$');
final RegExp _summary = RegExp(
  r'^Package has (\d+) warnings?(?: and (\d+) hints?)?\.$',
);
const String _validationStart = 'Package validation found the following';
const String _errorStart = 'Package validation found the following error';
const String _refusal = 'Sorry, your package is missing';
const String _serverNote = 'The server may enforce additional checks.';

/// Reads what `dart pub publish --dry-run` printed.
DryRunResult parseDryRun(PubRun run) {
  final List<String> lines = <String>[
    ...run.stdout.split('\n'),
    ...run.stderr.split('\n'),
  ].map((String line) => line.trimRight()).toList();
  String? publishing;
  String? archiveSize;
  int? warnings;
  int hints = 0;
  bool hasErrors = false;
  final List<String> validation = <String>[];
  bool inValidation = false;
  for (final String line in lines) {
    final Match? publishingMatch = _publishing.firstMatch(line);
    final Match? sizeMatch = _archiveSize.firstMatch(line);
    final Match? summaryMatch = _summary.firstMatch(line);
    if (publishingMatch != null) {
      publishing = '${publishingMatch[1]} ${publishingMatch[2]}';
    } else if (sizeMatch != null) {
      archiveSize = sizeMatch[1];
    } else if (summaryMatch != null) {
      warnings = int.parse(summaryMatch[1]!);
      hints = summaryMatch[2] == null ? 0 : int.parse(summaryMatch[2]!);
      inValidation = false;
    }
    if (line.startsWith(_errorStart) || line.startsWith(_refusal)) {
      hasErrors = true;
    }
    if (line.startsWith(_validationStart)) {
      inValidation = true;
    } else if (line == _serverNote || line.startsWith(_refusal)) {
      inValidation = false;
    }
    if (inValidation && line.trim().isNotEmpty) {
      validation.add(line);
    }
  }
  final List<String> details = validation.isNotEmpty
      ? validation
      : <String>[
          if (!(run.exitCode == 0 && warnings == 0 && !hasErrors))
            ...run.stderr
                .split('\n')
                .map((String line) => line.trimRight())
                .where((String line) => line.trim().isNotEmpty),
        ];
  return DryRunResult(
    exitCode: run.exitCode,
    publishing: publishing,
    archiveSize: archiveSize,
    warnings: warnings,
    hints: hints,
    hasErrors: hasErrors,
    details: details,
  );
}

/// Runs the dry-run with [runner] in every `packages/*/` of the repository
/// at [root] that has a `pubspec.yaml`, writes the report to [out] and
/// returns the exit code: 1 when a package has a warning or an error, or
/// when a line of the report would hold one of the [words].
int runPublishDryRun(
  String root,
  PubRunner runner,
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
    final DryRunResult result = parseDryRun(
      runner(p.join(root, 'packages', package)),
    );
    final List<String> details = <String>[
      for (final String line in result.details) '       ${line.trimLeft()}',
    ];
    final List<String> printed = details
        .where((String line) => words.wordsIn(line).isEmpty)
        .toList();
    int withheld = details.length - printed.length;
    String headline = _headline(package, result);
    if (words.wordsIn(headline).isNotEmpty) {
      withheld++;
      headline = 'FAIL $package: pub named a forbidden word';
    } else if (withheld > 0) {
      headline = headline.replaceFirst('ok   ', 'FAIL ');
    }
    if (withheld > 0) {
      printed.add(
        '       $withheld line${withheld == 1 ? '' : 's'} withheld: a '
        'forbidden word (spec 0007 D8) may not reach the public log.',
      );
    }
    if (!result.passed || withheld > 0) {
      failures++;
    }
    out.writeln(headline);
    printed.forEach(out.writeln);
  }
  if (failures > 0) {
    out.writeln(
      'Publish dry-run: $failures of ${packages.length} packages have '
      'warnings or errors.',
    );
    return 1;
  }
  out.writeln(
    'Publish dry-run: all ${packages.length} packages have 0 warnings.',
  );
  return 0;
}

String _headline(String package, DryRunResult result) {
  final String name = result.publishing ?? package;
  final String size = result.archiveSize == null
      ? ''
      : ' (${result.archiveSize})';
  final String hints = result.hints == 0
      ? ''
      : ', ${result.hints} hint${result.hints == 1 ? '' : 's'}';
  if (result.passed) {
    return 'ok   $name$size: 0 warnings$hints';
  }
  if (result.hasErrors) {
    return 'FAIL $name$size: pub would refuse it';
  }
  if (result.warnings == null) {
    return 'FAIL $name: pub printed no summary (exit code ${result.exitCode})';
  }
  final int count = result.warnings!;
  return 'FAIL $name$size: $count warning${count == 1 ? '' : 's'}$hints';
}
