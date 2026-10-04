// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Fails when a README's install snippet has a placeholder or `any`, does
/// not admit the package's own version or the upstream's latest major, or
/// when the README does not say to add the package alongside its upstream.
///
/// Usage, from `tool/`: `dart run bin/check_readme_snippets.dart
/// [--root <repository>] [--table <upstream_versions.yaml>]`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_tool/src/readme_snippets.dart';
import 'package:plugins_tool/src/repository.dart';

void main(List<String> arguments) {
  final Map<String, String> options = parseOptions(arguments, <String>{
    'root',
    'table',
  });
  final String tool = toolDirectory();
  exitCode = runSnippetCheck(
    options['root'] ?? repositoryRootOf(tool),
    options['table'] ?? p.join(tool, 'upstream_versions.yaml'),
    stdout,
  );
}
