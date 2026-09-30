// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Runs `dart pub publish --dry-run` in every package and fails when one has
/// a warning or an error. It reads pub.dev, as `pub get` does, and publishes
/// nothing.
///
/// Usage, from `tool/`: `dart run bin/publish_dry_run.dart
/// [--root <repository>]`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_tool/src/forbidden_words.dart';
import 'package:plugins_tool/src/publish_dry_run.dart';
import 'package:plugins_tool/src/repository.dart';

void main(List<String> arguments) {
  final Map<String, String> options = parseOptions(arguments, <String>{'root'});
  final String tool = toolDirectory();
  exitCode = runPublishDryRun(
    options['root'] ?? repositoryRootOf(tool),
    dartPubRunner(),
    ForbiddenWords.load(p.join(tool, 'words', 'words.txt')),
    stdout,
  );
}
