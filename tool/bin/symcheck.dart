// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Fails when a plugin's `ffiSymbols`, its native definitions and the
/// symbols its Dart code looks up disagree, outside
/// `tool/symcheck_allow.yaml`.
///
/// Usage, from `tool/`: `dart run bin/symcheck.dart [--root <repository>]
/// [--allow <symcheck_allow.yaml>]`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_tool/src/repository.dart';
import 'package:plugins_tool/src/symbols.dart';

void main(List<String> arguments) {
  final Map<String, String> options = parseOptions(arguments, <String>{
    'root',
    'allow',
  });
  final String tool = toolDirectory();
  exitCode = runSymbolCheck(
    options['root'] ?? repositoryRootOf(tool),
    parseSymbolAllowList(
      File(
        options['allow'] ?? p.join(tool, 'symcheck_allow.yaml'),
      ).readAsStringSync(),
    ),
    stdout,
  );
}
