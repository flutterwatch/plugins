// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Compares the `pana --json` report of each package with what the package
/// declares: every section full, except "Platform support" for a
/// watchOS-only package.
///
/// Usage, from `tool/`:
/// `dart run bin/pana_scores.dart --reports <dir> [--root <repository>]`,
/// where the directory holds one `<package>.json` per package.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_tool/src/forbidden_words.dart';
import 'package:plugins_tool/src/pana_scores.dart';
import 'package:plugins_tool/src/repository.dart';

void main(List<String> arguments) {
  final Map<String, String> options = parseOptions(arguments, <String>{
    'root',
    'reports',
  });
  final String? reports = options['reports'];
  if (reports == null) {
    stderr.writeln('usage: dart run bin/pana_scores.dart --reports <dir>');
    exitCode = 2;
    return;
  }
  final String tool = toolDirectory();
  exitCode = runPanaScores(
    options['root'] ?? repositoryRootOf(tool),
    reports,
    ForbiddenWords.load(p.join(tool, 'words', 'words.txt')),
    stdout,
  );
}
