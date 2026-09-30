// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Fails when a test or group name under `packages/*/test/` or
/// `packages/*/example/integration_test/` holds a forbidden word.
///
/// Usage, from `tool/`: `dart run bin/check_test_names.dart
/// [--root <repository>] [--pending <file>]`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_tool/src/forbidden_words.dart';
import 'package:plugins_tool/src/repository.dart';
import 'package:plugins_tool/src/test_names.dart';

void main(List<String> arguments) {
  final Map<String, String> options = parseOptions(arguments, <String>{
    'root',
    'pending',
  });
  final String tool = toolDirectory();
  exitCode = runTestNameStep(
    options['root'] ?? repositoryRootOf(tool),
    ForbiddenWords.load(p.join(tool, 'words', 'words.txt')),
    WordEntries.load(
      options['pending'] ?? p.join(tool, 'words', 'pending.txt'),
    ),
    stdout,
  );
}
