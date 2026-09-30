// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Fails when a package changed since its last publish without a new
/// version, when its top CHANGELOG heading is not its version, or when it is
/// at a pre-release.
///
/// Usage, from `tool/`: `dart run bin/check_versions.dart
/// [--root <repository>] [--published <published.yaml>]`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_tool/src/repository.dart';
import 'package:plugins_tool/src/versions.dart';

void main(List<String> arguments) {
  final Map<String, String> options = parseOptions(arguments, <String>{
    'root',
    'published',
  });
  final String tool = toolDirectory();
  exitCode = runVersionCheck(
    options['root'] ?? repositoryRootOf(tool),
    options['published'] ?? p.join(tool, 'published.yaml'),
    stdout,
  );
}
